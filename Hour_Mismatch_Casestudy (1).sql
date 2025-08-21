-- =====================================================================================
-- Final Query: Business Hour Mismatch Analysis (Version 9 - Final Corrected)
-- =====================================================================================

-- Step 0: Create a temporary function to solve the "unknown key" problem in the UberEats JSON.
CREATE TEMP FUNCTION getFirstMenuHours(json_string STRING)
RETURNS STRING
LANGUAGE js AS """
  try {
    const data = JSON.parse(json_string);
    const menuKeys = Object.keys(data);
    if (menuKeys.length === 0) {
      return '[]';
    }
    const firstMenuKey = menuKeys[0];
    const hours = data[firstMenuKey].sections[0].regularHours;
    return JSON.stringify(hours);
  } catch (e) {
    return '[]';
  }
""";

WITH
  -- Step 1a: Get the latest record for each UberEats store.
  ue_latest AS (
    SELECT
      b_name,
      vb_name,
      slug,
      response AS menu 
    FROM
      `arboreal-vision-339901.take_home_v2.virtual_kitchen_ubereats_hours`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY b_name, vb_name ORDER BY timestamp DESC) = 1
  ),

  -- Step 1b: Get the latest record for each Grubhub store.
  gh_latest AS (
    SELECT
      b_name,
      vb_name,
      slug,
      response
    FROM
      `arboreal-vision-339901.take_home_v2.virtual_kitchen_grubhub_hours`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY b_name, vb_name ORDER BY timestamp DESC) = 1
  ),

  -- Step 2a: Parse and flatten UberEats hours.
  ue_hours_parsed AS (
    SELECT
      ue.b_name,
      ue.vb_name,
      ue.slug AS ue_slug,
      day_index,
      JSON_EXTRACT_SCALAR(hours, '$.startTime') AS ue_start_time,
      JSON_EXTRACT_SCALAR(hours, '$.endTime') AS ue_end_time
    FROM
      ue_latest AS ue,
      UNNEST(JSON_QUERY_ARRAY(getFirstMenuHours(TO_JSON_STRING(ue.menu.data.menus)))) AS hours,
      UNNEST(JSON_EXTRACT_ARRAY(hours, '$.daysBitArray')) AS day_is_active WITH OFFSET AS day_index
    WHERE
      -- *** CRITICAL CORRECTION ***
      -- The array contains booleans (true/false), not integers (1/0).
      -- We check for the string 'true' instead of casting to a number.
      JSON_EXTRACT_SCALAR(day_is_active) = 'true'
  ),

  -- Step 2b: Parse and flatten Grubhub hours.
  gh_hours_parsed AS (
    SELECT
      gh.b_name,
      gh.vb_name,
      gh.slug AS gh_slug,
      CASE JSON_EXTRACT_SCALAR(daily_hours, '$.day_of_week')
        WHEN 'MONDAY' THEN 0 WHEN 'TUESDAY' THEN 1 WHEN 'WEDNESDAY' THEN 2
        WHEN 'THURSDAY' THEN 3 WHEN 'FRIDAY' THEN 4 WHEN 'SATURDAY' THEN 5
        WHEN 'SUNDAY' THEN 6
      END AS day_index,
      JSON_EXTRACT_SCALAR(time_range, '$.start_time') AS gh_start_time,
      JSON_EXTRACT_SCALAR(time_range, '$.end_time') AS gh_end_time
    FROM
      gh_latest AS gh,
      UNNEST(JSON_QUERY_ARRAY(gh.response, '$.availability.available_hours')) AS daily_hours,
      UNNEST(JSON_QUERY_ARRAY(daily_hours, '$.time_ranges')) AS time_range
  ),
  
  -- Step 3: Join the clean datasets.
  comparison_data AS (
    SELECT
      COALESCE(gh.b_name, ue.b_name) as b_name,
      COALESCE(gh.vb_name, ue.vb_name) as vb_name,
      gh.gh_slug,
      ue.ue_slug,
      gh.gh_start_time,
      gh.gh_end_time,
      ue.ue_start_time,
      ue.ue_end_time,
      COALESCE(gh.day_index, ue.day_index) as day_index,
      CASE COALESCE(gh.day_index, ue.day_index)
        WHEN 0 THEN 'Monday' WHEN 1 THEN 'Tuesday' WHEN 2 THEN 'Wednesday'
        WHEN 3 THEN 'Thursday' WHEN 4 THEN 'Friday' WHEN 5 THEN 'Saturday'
        WHEN 6 THEN 'Sunday'
      END as day_of_week
    FROM
      gh_hours_parsed AS gh
      FULL OUTER JOIN ue_hours_parsed AS ue 
        ON  gh.b_name = ue.b_name 
        AND gh.vb_name = ue.vb_name 
        AND gh.day_index = ue.day_index
)

-- Step 4: Apply final business logic.
SELECT
  gh_slug AS `Grubhub_slug`,
  CONCAT(day_of_week, ': ', IFNULL(gh_start_time, "CLOSED"), ' - ', IFNULL(gh_end_time, "CLOSED")) AS `Grubhub_Business_Hours`,
  ue_slug AS `Uber_Eats_slug`,
  CONCAT(day_of_week, ': ', IFNULL(ue_start_time, "CLOSED"), ' - ', IFNULL(ue_end_time, "CLOSED")) AS `Uber_Eats_Business_Hours`,
  CASE
    WHEN ue_start_time IS NULL OR gh_start_time IS NULL THEN 'Out of Range'
    WHEN CAST(gh_start_time AS TIME) >= CAST(ue_start_time AS TIME) AND CAST(gh_end_time AS TIME) <= CAST(ue_end_time AS TIME) THEN 'In Range'
    WHEN (
        TIME_DIFF(CAST(ue_start_time AS TIME), CAST(gh_start_time AS TIME), MINUTE) BETWEEN 0 AND 5 AND
        CAST(gh_end_time AS TIME) <= CAST(ue_end_time AS TIME)
      ) OR (
        TIME_DIFF(CAST(gh_end_time AS TIME), CAST(ue_end_time AS TIME), MINUTE) BETWEEN 0 AND 5 AND
        CAST(gh_start_time AS TIME) >= CAST(ue_start_time AS TIME)
      )
    THEN 'Out of Range with 5 mins difference'
    ELSE 'Out of Range'
  END AS `is_out_of_range`
FROM 
  comparison_data
ORDER BY
  b_name,
  vb_name,
  day_index;