# bigquery-hours-mismatch-analysis
A BigQuery SQL project to analyze business hour discrepancies between food delivery platforms.
# Business Hours Mismatch Analysis: UberEats vs. Grubhub

## Problem Statement

This project analyzes and identifies discrepancies in restaurant business hours listed on two major food delivery platforms: UberEats and Grubhub. Mismatched hours can lead to canceled orders, poor customer experience, and lost revenue. The goal is to create a clear report that flags these inconsistencies for correction. For this analysis, UberEats is considered the "source of truth."

## The Data

The analysis uses two tables in Google BigQuery:
- `arboreal-vision-339901.take_home_v2.virtual_kitchen_ubereats_hours`
- `arboreal-vision-339901.take_home_v2.virtual_kitchen_grubhub_hours`

Business hours are stored in complex, nested JSON objects within these tables.

## The Solution

The SQL query (`business_hours_mismatch.sql`) performs the following steps:
1.  **Creates a JavaScript UDF** to handle the complex structure of the UberEats JSON, where menu IDs are unknown.
2.  Selects the most **recent record** for each store to ensure the data is current.
3.  **Parses and unnests** the JSON from both sources to create a clean, row-by-row list of hours for each day.
4.  **Standardizes** the day of the week to a common format (a number 0-6).
5.  Uses a `FULL OUTER JOIN` to merge the data and find all discrepancies, including when a store is listed as open on one platform but closed on another.
6.  **Classifies** each mismatch as "In Range", "Out of Range with 5 mins difference", or "Out of Range".

## Results

The output of the query is provided in `mismatch_results.csv`. This file contains the final report, showing the business hours from both platforms side-by-side and the classification of any mismatch for each day. This report can be used by an operations team to identify and contact restaurants to correct their listings.
