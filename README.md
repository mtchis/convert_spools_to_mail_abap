
# Automatic Report Email Notification

## Overview

This development automatically sends an email with spool report attachments after the Electronic Bank Statement (EBS) background processing is completed.

The program:

1. Retrieves recipient information from the parent background job.
2. Waits for all expected spool requests to be generated.
3. Collects spool contents.
4. Builds an HTML email body.
5. Sends the email together with spool report attachments.

---

## Process Flow

### 1. Get Parent Job Information

The program obtains the current background job runtime information using:

```abap
CALL FUNCTION 'GET_JOB_RUNTIME_INFO'
```

Retrieved values:

- Job Name
- Job Count

The parent job details are then read from table `TBTCO`.

```abap
SELECT SINGLE ...
FROM TBTCO
```

---

### 2. Determine Email Recipient

If the parent job contains recipient information:

- `RECOBJTYPE = 'RECIPIENT'`
- `RECOBJKEY` is populated

the recipient object is built and stored.

Example:

```abap
ls_rec_obj-objtype = 'RECIPIENT'.
ls_rec_obj-objkey  = ls_tbtco_parent-recobjkey.
```

This allows the child job to inherit the recipient list from the parent background job.

---

### 3. Read Waiting Time Configuration

The waiting timeout is maintained in TVARVC.

Parameter:

| TVARVC Name | Description |
|------------|-------------|
| Z_WAIT_TIME | Waiting time (minutes) |

```abap
SELECT SINGLE low
FROM tvarvc
WHERE name = 'Z_WAIT_TIME'.
```

Timeout is converted into seconds.

---

### 4. Wait for Expected Spools

The process continuously checks table `TBTCP` for completed spool jobs.

Selection criteria:

- Current execution date
- Status = `F` (Finished)
- Processing text matches:

```text
RFEBKA00-{JOBCOUNT}
```

The program waits until:

- At least 2 spool requests are found
- OR timeout is reached

```abap
WHILE lv_waited <= lv_timeout.
```

Default expectation:

```abap
lv_expected = 2.
```

---

### 5. Collect Spool IDs

All spool request numbers (`LISTIDENT`) are collected.

Steps:

1. Remove blank spool IDs
2. Eliminate duplicates
3. Store unique spool numbers

Example:

```abap
APPEND ls_tbtcp-listident TO lt_rqident.
```

---

### 6. Create Email Content

An HTML email body is generated.

Example content:

```html
Dear team,

This is an automated email generated from the SAP batch job
RFEB1B00 – Bank Statement Report

and the SAP batch job
RFEBKA00 – Bank Statement Posting – Processing Statistic.

The EBS has been successfully uploaded,
and the output report is attached for your review.

Date: YYYY-MM-DD

Regards,
```

Email content type:

```abap
DOC_TYPE = 'HTM'
```

---

### 7. Retrieve Spool Contents

For each spool request:

#### Determine Spool Type

```abap
RSPO_GET_TYPE_SPOOLJOB
```

#### Read Spool Data

```abap
RSPO_RETURN_SPOOLJOB
```

Returned data is stored into:

```abap
SO_ALI
```

and aggregated into:

```abap
LT_FINNAL
```

for email attachments.

---

### 8. Build Attachment Metadata

For each spool:

- Attachment name is generated dynamically
- File size is calculated
- Packing information is created

Attachment naming format:

```text
Spool_ID_<SPOOL_NUMBER>_<DATE>
```

Example:

```text
Spool_ID_12345678_20261015
```

---

### 9. Send Email

The email is sent using:

```abap
SO_DOCUMENT_SEND_API1
```

Components:

| Component | Description |
|------------|-------------|
| HTML Body | Email message |
| Attachments | Spool reports |
| Receivers | Parent job recipient list |

Configuration:

```abap
PUT_IN_OUTBOX = 'X'
COMMIT_WORK   = 'X'
```

---

## Error Handling

The program handles exceptions such as:

### Runtime Information

- NO_RUNTIME_INFO

### Spool Access

- NO_SUCH_JOB
- JOB_CONTAINS_NO_DATA
- NO_PERMISSION
- CAN_NOT_ACCESS
- READ_ERROR
- TYPE_NO_MATCH

### Email Sending

- DOCUMENT_NOT_SENT
- TOO_MANY_RECEIVERS
- PARAMETER_ERROR
- X_ERROR

A generic exception handler is also implemented:

```abap
CATCH cx_root.
```

---

## Dependencies

### Tables

- TBTCO
- TBTCP
- TVARVC

### Function Modules

- GET_JOB_RUNTIME_INFO
- RSPO_GET_TYPE_SPOOLJOB
- RSPO_RETURN_SPOOLJOB
- SO_DOCUMENT_SEND_API1

---

## Configuration

### TVARVC

Maintain parameter:

| Parameter | Example |
|------------|-----------|
| Z_WAIT_TIME | 60 |

Meaning:

```text
Maximum waiting time in minutes
for spool generation.
```

---

## Business Scenario

This solution is designed for Electronic Bank Statement processing:

### Report 1

```text
RFEB1B00
Bank Statement Report
```

### Report 2

```text
RFEBKA00
Bank Statement Posting – Processing Statistic
```

After successful processing:

1. Wait for both spool outputs.
2. Convert spool content into email attachments.
3. Send automated notification email.
4. Reuse recipient information from the parent scheduled job.

This eliminates manual spool checking and ensures business users receive the EBS processing reports automatically.
