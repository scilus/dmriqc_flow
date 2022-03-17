#!/usr/bin/python3.7

import json
import numpy as np
import os
import pandas as pd

before = np.load("${before_mat}")
after = np.load("${after_mat}")

#Ratio
before[np.where(before==0)] = np.inf
ratio = after / before

#Result
indexes = np.where(ratio >= np.nanmax(ratio) - 1*np.nanstd(ratio))

pair_indexes = []

for curr_index in range(len(indexes[0])):
	val_1 = indexes[0][curr_index]
	val_2 = indexes[1][curr_index]

	if before[val_1,val_2] <= 1:
		continue

	if val_1 > val_2:
		pair_indexes.append((val_2, val_1))
	else:
		pair_indexes.append((val_1, val_2))

unique_pair = np.unique(pair_indexes, axis=0)

#Load labels txt
f = open("${labels}")
labels = json.load(f)

pair_name = []
val_before = []
val_ratio = []
val_after = []

for curr_index in unique_pair:
	pair_name.append(labels[[*labels.keys()][curr_index[0]]] + "_to_" +\
					 labels[[*labels.keys()][curr_index[1]]])
	val_before.append(before[curr_index[0],curr_index[1]])
	val_ratio.append(ratio[curr_index[0],curr_index[1]])
	val_after.append(after[curr_index[0],curr_index[1]])

# Pandas dataframe "Pair de string" before ratio
df = pd.DataFrame({'Connections': pair_name,
				   'sc_ratio': val_ratio,
                   'sc_atlas': val_before,
	               'sc_in_lesion': val_after})

df = df.sort_values(["sc_ratio", "sc_atlas"], ascending = [True, False])

# Keep the first 10 entries
df = df[0:10]

# Save dataframe as csv
df.to_csv("${output_file}", index=False)
