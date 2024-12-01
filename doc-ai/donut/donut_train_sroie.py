
import os
import re
import json
from collections import Counter
from itertools import chain
from pathlib import Path
from typing import List, Dict, Union, Tuple, Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import torch
from PIL import Image
from sklearn.model_selection import StratifiedKFold
from torch.utils.data import DataLoader
from transformers import (
    DonutProcessor,
    VisionEncoderDecoderConfig,
    VisionEncoderDecoderModel,
    get_scheduler,
    Trainer,
    TrainingArguments
)
from datasets import load_dataset, Dataset, Image as ds_img
from polyleven import levenshtein  # a faster version of levenshtein

# Load the SROIE-2019-V2 dataset
ds = load_dataset("rth/sroie-2019-v2")

# Preprocess the data
def preprocess(example):
    example['text'] = "; ".join([f"{k}: {v}" for k, v in example['objects']['entities'].items()])
    return example

ds = ds.map(preprocess)

# Initialize the processor and model
processor = DonutProcessor.from_pretrained("naver-clova-ix/donut-base")
config = VisionEncoderDecoderConfig.from_pretrained("naver-clova-ix/donut-base")
model = VisionEncoderDecoderModel.from_pretrained("naver-clova-ix/donut-base", config=config)

# Set up training arguments and data loaders
training_args = TrainingArguments(
    output_dir="./donut-sroie",
    per_device_train_batch_size=4,
    per_device_eval_batch_size=4,
    num_train_epochs=3,
    learning_rate=5e-5,
    evaluation_strategy="epoch",
    save_strategy="epoch",
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=ds["train"],
    eval_dataset=ds["validation"],
)

# Train the model
trainer.train()