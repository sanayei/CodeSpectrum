import json
import random
import re
from pathlib import Path
from typing import Any, List, Tuple

import numpy as np
import pytorch_lightning as pl
import torch
from datasets import load_dataset
from donut import JSONParseEvaluator
from nltk import edit_distance
from pytorch_lightning.callbacks import EarlyStopping
from torch.utils.data import DataLoader, Dataset
from transformers import DonutProcessor, VisionEncoderDecoderConfig, VisionEncoderDecoderModel

# Set up environment
# !pip install -q transformers datasets sentencepiece pytorch-lightning donut-python

added_tokens = []

class DonutDataset(Dataset):
    def __init__(
        self,
        dataset,
        max_length: int,
        split: str,
        ignore_id: int = -100,
        task_start_token: str = "<s>",
        prompt_end_token: str = None,
    ):
        super().__init__()

        self.max_length = max_length
        self.split = split
        self.ignore_id = ignore_id
        self.task_start_token = task_start_token
        self.prompt_end_token = prompt_end_token if prompt_end_token else task_start_token

        self.dataset = dataset
        self.dataset_length = len(self.dataset)

        self.gt_token_sequences = []
        for sample in self.dataset:
            entities = json.loads(sample["entities"])
            self.gt_token_sequences.append(
                self.json2token(
                    entities,
                    update_special_tokens_for_json_key=self.split == "train"
                ) + processor.tokenizer.eos_token
            )

        self.add_tokens([self.task_start_token, self.prompt_end_token])
        self.prompt_end_token_id = processor.tokenizer.convert_tokens_to_ids(self.prompt_end_token)

    def json2token(self, obj: Any, update_special_tokens_for_json_key: bool = True):
        if type(obj) == dict:
            output = ""
            for k in obj.keys():
                if update_special_tokens_for_json_key:
                    self.add_tokens([fr"<s_{k}>", fr"</s_{k}>"])
                output += (
                    fr"<s_{k}>"
                    + self.json2token(obj[k], update_special_tokens_for_json_key)
                    + fr"</s_{k}>"
                )
            return output
        else:
            return str(obj)

    def add_tokens(self, list_of_tokens: List[str]):
        newly_added_num = processor.tokenizer.add_tokens(list_of_tokens)
        if newly_added_num > 0:
            model.decoder.resize_token_embeddings(len(processor.tokenizer))
            added_tokens.extend(list_of_tokens)

    def __len__(self) -> int:
        return self.dataset_length

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        sample = self.dataset[idx]

        pixel_values = processor(sample["image"], random_padding=self.split == "train", return_tensors="pt").pixel_values
        pixel_values = pixel_values.squeeze()

        target_sequence = self.gt_token_sequences[idx]
        input_ids = processor.tokenizer(
            target_sequence,
            add_special_tokens=False,
            max_length=self.max_length,
            padding="max_length",
            truncation=True,
            return_tensors="pt",
        )["input_ids"].squeeze(0)

        labels = input_ids.clone()
        labels[labels == processor.tokenizer.pad_token_id] = self.ignore_id
        return pixel_values, labels, target_sequence

class DonutModelPLModule(pl.LightningModule):
    def __init__(self, config, processor, model):
        super().__init__()
        self.config = config
        self.processor = processor
        self.model = model

    def training_step(self, batch, batch_idx):
        pixel_values, labels, _ = batch
        outputs = self.model(pixel_values, labels=labels)
        loss = outputs.loss
        self.log("train_loss", loss)
        return loss

    def validation_step(self, batch, batch_idx, dataset_idx=0):
        pixel_values, labels, answers = batch
        batch_size = pixel_values.shape[0]
        decoder_input_ids = torch.full((batch_size, 1), self.model.config.decoder_start_token_id, device=self.device)

        outputs = self.model.generate(
            pixel_values,
            decoder_input_ids=decoder_input_ids,
            max_length=max_length,
            early_stopping=True,
            pad_token_id=self.processor.tokenizer.pad_token_id,
            eos_token_id=self.processor.tokenizer.eos_token_id,
            use_cache=True,
            num_beams=1,
            bad_words_ids=[[self.processor.tokenizer.unk_token_id]],
            return_dict_in_generate=True,
        )

        predictions = []
        for seq in self.processor.tokenizer.batch_decode(outputs.sequences):
            seq = seq.replace(self.processor.tokenizer.eos_token, "").replace(self.processor.tokenizer.pad_token, "")
            seq = re.sub(r"<.*?>", "", seq, count=1).strip()
            predictions.append(seq)

        scores = []
        for pred, answer in zip(predictions, answers):
            pred = re.sub(r"(?:(?<=>) | (?=</s_))", "", pred)
            answer = answer.replace(self.processor.tokenizer.eos_token, "")
            scores.append(edit_distance(pred, answer) / max(len(pred), len(answer)))

            if self.config.get("verbose", False) and len(scores) == 1:
                print(f"Prediction: {pred}")
                print(f"    Answer: {answer}")
                print(f" Normed ED: {scores[0]}")

        self.log("val_edit_distance", np.mean(scores))
        return scores

    def configure_optimizers(self):
        optimizer = torch.optim.Adam(self.parameters(), lr=self.config.get("lr"))
        return optimizer

    def train_dataloader(self):
        return train_dataloader

    def val_dataloader(self):
        return val_dataloader

# Load custom dataset
train_dataset = load_dataset("your_dataset_name", split="train")
val_dataset = load_dataset("your_dataset_name", split="validation")

# Configure model and processor
image_size = [1280, 960]
max_length = 768

config = VisionEncoderDecoderConfig.from_pretrained("naver-clova-ix/donut-base")
config.encoder.image_size = image_size
config.decoder.max_length = max_length

processor = DonutProcessor.from_pretrained("naver-clova-ix/donut-base")
model = VisionEncoderDecoderModel.from_pretrained("naver-clova-ix/donut-base", config=config)

processor.image_processor.size = image_size[::-1]
processor.image_processor.do_align_long_axis = False

model.config.pad_token_id = processor.tokenizer.pad_token_id
model.config.decoder_start_token_id = processor.tokenizer.convert_tokens_to_ids(['<s_invoice>'])[0]

# Create PyTorch datasets and dataloaders
train_dataset = DonutDataset(train_dataset, max_length=max_length,
                             split="train", task_start_token="<s_invoice>", prompt_end_token="<s_invoice>")

val_dataset = DonutDataset(val_dataset, max_length=max_length,
                             split="validation", task_start_token="<s_invoice>", prompt_end_token="<s_invoice>")

train_dataloader = DataLoader(train_dataset, batch_size=1, shuffle=True, num_workers=4)
val_dataloader = DataLoader(val_dataset, batch_size=1, shuffle=False, num_workers=4)

# Configure training
config = {
    "max_epochs": 30,
    "val_check_interval": 0.2,
    "check_val_every_n_epoch": 1,
    "gradient_clip_val": 1.0,
    "num_training_samples_per_epoch": len(train_dataset),
    "lr": 3e-5,
    "train_batch_sizes": [8],
    "val_batch_sizes": [1],
    "num_nodes": 1,
    "warmup_steps": len(train_dataset) // 8 * 3, # 10% of total steps
    "result_path": "./result",
    "verbose": True,
}

model_module = DonutModelPLModule(config, processor, model)
early_stop_callback = EarlyStopping(monitor="val_edit_distance", patience=3, verbose=False, mode="min")

trainer = pl.Trainer(
    accelerator="gpu",
    devices=1,
    max_epochs=config.get("max_epochs"),
    val_check_interval=config.get("val_check_interval"),
    check_val_every_n_epoch=config.get("check_val_every_n_epoch"),
    gradient_clip_val=config.get("gradient_clip_val"),
    precision=16,
    num_sanity_val_steps=0,
    callbacks=[early_stop_callback],
)

trainer.fit(model_module)

# Evaluate
model_module.model.eval()
model_module.model.to("cuda" if torch.cuda.is_available() else "cpu")

output_list = []
accs = []

val_dataset = load_dataset("your_dataset_name", split="validation")

for idx, sample in enumerate(val_dataset):
    pixel_values = processor(sample["image"].convert("RGB"), return_tensors="pt").pixel_values
    pixel_values = pixel_values.to(model_module.device)

    task_prompt = "<s_invoice>"
    decoder_input_ids = processor.tokenizer(task_prompt, add_special_tokens=False, return_tensors="pt").input_ids
    decoder_input_ids = decoder_input_ids.to(model_module.device)

    outputs = model_module.model.generate(
        pixel_values,
        decoder_input_ids=decoder_input_ids,
        max_length=model_module.model.decoder.config.max_position_embeddings,
        early_stopping=True,
        pad_token_id=processor.tokenizer.pad_token_id,
        eos_token_id=processor.tokenizer.eos_token_id,
        use_cache=True,
        num_beams=1,
        bad_words_ids=[[processor.tokenizer.unk_token_id]],
        return_dict_in_generate=True,
    )

    seq = processor.batch_decode(outputs.sequences)[0]
    seq = seq.replace(processor.tokenizer.eos_token, "").replace(processor.tokenizer.pad_token, "")
    seq = re.sub(r"<.*?>", "", seq, count=1).strip()
    seq = processor.token2json(seq)

    ground_truth = json.loads(sample["entities"])
    evaluator = JSONParseEvaluator()
    score = evaluator.cal_acc(seq, ground_truth)

    accs.append(score)
    output_list.append(seq)

scores = {"accuracies": accs, "mean_accuracy": np.mean(accs)}
print(scores)
