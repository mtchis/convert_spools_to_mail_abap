DATA: ls_rec_obj         TYPE swotobjid,
        lv_parent_jobname  TYPE tbtcjob-jobname,
        lv_parent_jobcount TYPE tbtcjob-jobcount,
        ls_tbtco_parent    TYPE tbtco.

  CALL FUNCTION 'GET_JOB_RUNTIME_INFO'
    IMPORTING
      jobname         = lv_parent_jobname
      jobcount        = lv_parent_jobcount
    EXCEPTIONS
      no_runtime_info = 1
      OTHERS          = 2.

  SELECT SINGLE jobname jobcount recobjtype recobjkey reclogsys recdescrib
    INTO CORRESPONDING FIELDS OF ls_tbtco_parent
    FROM tbtco
   WHERE jobname  = lv_parent_jobname
     AND jobcount = lv_parent_jobcount.

  IF sy-subrc = 0
     AND ls_tbtco_parent-recobjtype = 'RECIPIENT'
     AND ls_tbtco_parent-recobjkey  IS NOT INITIAL.

    CLEAR: ls_rec_obj.
    ls_rec_obj-logsys = ls_tbtco_parent-reclogsys.
    ls_rec_obj-describe = ls_tbtco_parent-recdescrib.
    ls_rec_obj-objtype = ls_tbtco_parent-recobjtype.  " = 'RECIPIENT'
    ls_rec_obj-objkey  = ls_tbtco_parent-recobjkey.
  ENDIF.

    METHOD convert_spools_to_mail.
    "=== Types ===
    TYPES: tt_rqident TYPE STANDARD TABLE OF tsp01-rqident WITH EMPTY KEY.
    DATA:
      ls_date  TYPE sy-datum, "current day
      lv_date  TYPE string, "format day as YYYY-MM-DD
      ls_prtxt TYPE tbtcp-prtxt.


    DATA: lt_tbtcp    TYPE TABLE OF tbtcp,
          lt_rqident  TYPE STANDARD TABLE OF tsp01-rqident WITH EMPTY KEY,
          lv_expected TYPE i VALUE 2,       " 2 spool
          lv_timeout  TYPE i ,      "1 hour to waiting to trace 2 spools completed
          lv_waited   TYPE i VALUE 0.

    DATA: lr_send_request TYPE REF TO cl_bcs,
          lr_document     TYPE REF TO cl_document_bcs,
          lr_recipient    TYPE REF TO if_recipient_bcs,
          lt_body         TYPE soli_tab.

    SELECT SINGLE low INTO @DATA(lv_wait_time)          
        FROM tvarvc
        WHERE name = 'Z_WAIT_TIME'.

    lv_timeout = ( CONV i( lv_wait_time ) ) * 60.
    CLEAR ls_prtxt.
    CONCATENATE 'RFEBKA00-' i_jobcount INTO ls_prtxt .
    ls_date = sy-datum.
    lv_date = |{ sy-datum DATE = ISO }|. "format as Date: YYYY-MM-DD
    WHILE lv_waited <= lv_timeout.
      CLEAR lt_tbtcp.
      SELECT *
        FROM tbtcp
        INTO TABLE lt_tbtcp
        WHERE sdldate = ls_date
        AND status = 'F'
        AND prtxt = ls_prtxt.
*        AND jobname = 'RFEBKA00-EL BANK STATEM'.

      DELETE lt_tbtcp WHERE listident IS INITIAL.


      CLEAR lt_rqident.
      LOOP AT lt_tbtcp INTO DATA(ls_tbtcp).
        IF ls_tbtcp-listident IS NOT INITIAL.
          APPEND ls_tbtcp-listident TO lt_rqident.
        ENDIF.
      ENDLOOP.

      SORT lt_rqident BY table_line.
      DELETE ADJACENT DUPLICATES FROM lt_rqident COMPARING table_line.

      IF lines( lt_rqident ) >= lv_expected. "Ff find out 2 spool target, loop will stop
        EXIT.
      ENDIF.

      WAIT UP TO 2 SECONDS.
      lv_waited = lv_waited + 2.
    ENDWHILE.
    IF lt_rqident IS INITIAL.
      MESSAGE 'Job no found to send mail' TYPE 'S' DISPLAY LIKE 'E'. 
    ENDIF.
    IF lt_rqident IS NOT INITIAL.
      TRY. "catch error
          DATA: doctype       TYPE tsp01-rqdoctype,
                startline     TYPE i VALUE 1,
                endline       TYPE i VALUE 0,
                so_ali        TYPE soli_tab,
                lt_finnal     TYPE soli_tab,
                ls_ali        TYPE soli,
                desired_type  TYPE soodk-objtp,
                sp_lang       TYPE tst01-dlang,
                btc_spool(10),
                document_data TYPE sodocchgi1,
                mail_title    TYPE sodocchgi1-obj_descr VALUE 'Electronic Bank Statement Report',
                real_type     TYPE soodk-objtp,
                rec_tab       TYPE somlreci1,
                lt_rec_tab    TYPE STANDARD TABLE OF somlreci1.

          MOVE: v_parent_recipient  TO rec_tab-receiver, "get spool mail list from parent job
                'J'      TO rec_tab-rec_type.
          APPEND rec_tab TO lt_rec_tab.

          DATA: num_lines TYPE i.
          DATA: line_size TYPE i.

          DATA: lt_packing TYPE TABLE OF sopcklsti1.
          DATA: "object_header TYPE TABLE OF solisti1,
            lt_mailtxt   TYPE TABLE OF solisti1 INITIAL SIZE 10,
*            lt_mailtxt   TYPE soli_tab,
            ls_mailtxt   TYPE solisti1,
            lv_start     TYPE i,
            lv_tab_lines TYPE sy-tabix,
            lwa_content  TYPE solisti1.


*          APPEND |Dear team,\n| TO lt_mailtxt.
*          APPEND |This is an automated email generated from the SAP batch job RFEB1B00 – Bank Statement Report| TO lt_mailtxt.
*          APPEND |And SAP batch job RFEBKA00 - Bank Statement Posting - Processing Statistic. | TO lt_mailtxt.
*          APPEND |The job completed successfully, and the output report is attached for your review.| TO lt_mailtxt.
*          APPEND |No action is required unless discrepancies are identified. | TO lt_mailtxt.
*          APPEND |Date: { sy-datum } \n| TO lt_mailtxt.
*          APPEND |Regards,| TO lt_mailtxt.
          CLEAR ls_mailtxt.
          ls_mailtxt-line  = '<HTML>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = '<BODY>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = 'Dear team,<br><br>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = 'This is an automated email generated from the SAP batch job <b>RFEB1B00 – Bank Statement Report</b>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = 'and the SAP batch job <b>RFEBKA00 – Bank Statement Posting – Processing Statistic.</b><br><br>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = 'The EBS has been successfully uploaded, and the output report is attached for your review.<br><br><br>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = |Date: { lv_date }<br><br><br>|.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = 'Regards,<br><br>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = '</BODY>'.
          APPEND ls_mailtxt TO lt_mailtxt.

          CLEAR ls_mailtxt.
          ls_mailtxt-line  = '</HTML>'.
          APPEND ls_mailtxt TO lt_mailtxt.


          DESCRIBE TABLE lt_mailtxt LINES DATA(lv_lines).
          READ TABLE lt_mailtxt INDEX lv_lines INTO ls_mailtxt.
          IF sy-subrc IS INITIAL.
            document_data-doc_size = ( lv_lines - 1 ) * 255 + strlen( ls_mailtxt ).
          ENDIF.

          APPEND INITIAL LINE TO lt_packing ASSIGNING FIELD-SYMBOL(<ls_packing>). "Body mail content
          <ls_packing>-transf_bin = space. "abap_true.
          <ls_packing>-head_start = 1.
          <ls_packing>-head_num = 0.
          <ls_packing>-body_start = 1.
          <ls_packing>-body_num = lines( lt_mailtxt ).
          <ls_packing>-doc_type = 'HTM'. "'RAW'.
          <ls_packing>-obj_descr = document_data-obj_descr.

          document_data-obj_descr = mail_title.
          CONDENSE document_data-obj_descr.
          document_data-obj_name = 'Liste'(sls).
          document_data-sensitivty = 'O'.

          document_data-obj_langu = sy-langu.

          lv_start      = 1.
          LOOP AT lt_rqident ASSIGNING FIELD-SYMBOL(<rq>).
            CALL FUNCTION 'RSPO_GET_TYPE_SPOOLJOB'
              EXPORTING
                rqident        = <rq>
              IMPORTING
                doctype        = doctype
              EXCEPTIONS
                can_not_access = 1
                OTHERS         = 2.
            IF sy-subrc <> 0.
              MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 RAISING can_not_access.
            ENDIF.

            REFRESH so_ali.
            CALL FUNCTION 'RSPO_RETURN_SPOOLJOB' "get spool data from spool list
              EXPORTING
                rqident              = <rq>
                first_line           = startline
                last_line            = endline
                desired_type         = desired_type
              IMPORTING
                real_type            = real_type
                sp_lang              = sp_lang
              TABLES
                buffer               = so_ali
              EXCEPTIONS
                no_such_job          = 1
                job_contains_no_data = 2
                selection_empty      = 3
                no_permission        = 4
                can_not_access       = 5
                read_error           = 6
                type_no_match        = 7
                OTHERS               = 8.
            CASE sy-subrc.
              WHEN 0.
              WHEN 1.
                MESSAGE 'no_such_job' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 2.
                MESSAGE 'job_contains_no_data' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 3.
                MESSAGE 'selection_empty' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 4.
                MESSAGE 'no_permission' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 5.
                MESSAGE 'can_not_access.' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 6.
                MESSAGE 'read_error' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 7.
                MESSAGE 'type_no_match' TYPE 'S' DISPLAY LIKE 'E'.
              WHEN 8.
                EXIT.
            ENDCASE.
            IF sy-subrc = 0.
              APPEND LINES OF so_ali TO lt_finnal. "collect 2 files spool
            ENDIF.


            APPEND INITIAL LINE TO lt_packing ASSIGNING <ls_packing>. "packing for file attachment
            <ls_packing>-transf_bin = 'X'.
            <ls_packing>-body_start = lv_start.
            <ls_packing>-obj_descr = document_data-obj_descr.
            DESCRIBE TABLE so_ali LINES <ls_packing>-body_num.
            <ls_packing>-doc_type = real_type. "file type spool job
            <ls_packing>-obj_descr  = |Spool_ID_{ <rq> }_{ sy-datum }|.
            CLASS cl_abap_char_utilities DEFINITION LOAD.
            IF cl_abap_char_utilities=>charsize > 1. " system is Unicode
              line_size = 510.
            ELSE.
              line_size = 255.
            ENDIF.
            READ TABLE lt_finnal INTO ls_ali INDEX <ls_packing>-body_num.
            <ls_packing>-doc_size = ( <ls_packing>-body_num - 1 ) * line_size
                             + strlen( ls_ali ).

            lv_start = lines( so_ali ) + 1. "2 file

          ENDLOOP.

          CALL FUNCTION 'SO_DOCUMENT_SEND_API1'        "Send mail with attachment
            EXPORTING
              document_data              = document_data
*             PUT_IN_OUTBOX              = ' '
*             sender_address             = sender_address
              put_in_outbox              = abap_true
              commit_work                = abap_true
*             sender_address_type        = sender_address_type
*     IMPORTING
*             SENT_TO_ALL                =
*             NEW_OBJECT_ID              =
            TABLES
              packing_list               = lt_packing
              object_header              = lt_mailtxt
              contents_txt               = lt_mailtxt
              contents_bin               = lt_finnal "File attachment
*             CONTENTS_TXT               =
*             CONTENTS_HEX               =
*             OBJECT_PARA                =
*             OBJECT_PARB                =
              receivers                  = lt_rec_tab "spool mail list from parent job
            EXCEPTIONS
              too_many_receivers         = 1
              document_not_sent          = 2
              document_type_not_exist    = 3
              operation_no_authorization = 4
              parameter_error            = 5
              x_error                    = 6
              enqueue_error              = 7
              OTHERS                     = 8.
          IF sy-subrc <> 0.
          ENDIF.
          CLEAR: so_ali, lt_finnal, lt_mailtxt, ls_mailtxt, lt_packing, document_data, lv_start.
        CATCH cx_root.
          MESSAGE 'Z_JOB_NAME - Sending email failed!!!' TYPE 'S' DISPLAY LIKE 'E'.
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  
