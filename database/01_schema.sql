/*
 * Synthetic Oracle proof-of-concept schema only.
 *
 * Production DDL, constraints, triggers, and indexes have not been reproduced
 * because they are unknown. This schema exists only to prove PFC/HER/HEF
 * resolution and future mutation behavior. Production deployment requires a
 * separate schema review. No real patient, payor, claim, or production data is
 * permitted in these tables.
 */

CREATE TABLE payors (
    payor_guid      VARCHAR2(36)  NOT NULL,
    payor_type_guid VARCHAR2(36)  NOT NULL,
    payor_name      VARCHAR2(128) NOT NULL,
    payor_id        VARCHAR2(50),
    rec_ent_date    DATE          NOT NULL,
    rec_ent_user    VARCHAR2(36)  NOT NULL,
    rec_mod_date    DATE,
    rec_mod_user    VARCHAR2(36),
    CONSTRAINT pk_payors PRIMARY KEY (payor_guid)
);

CREATE TABLE pfc (
    pfc_guid                VARCHAR2(36) NOT NULL,
    payor_guid              VARCHAR2(36),
    billing_form_type_code  VARCHAR2(2)  NOT NULL,
    billing_form_code       VARCHAR2(10) NOT NULL,
    default_media_type      VARCHAR2(2)  NOT NULL,
    form_template_guid      VARCHAR2(36),
    plan_guid               VARCHAR2(36),
    type_of_bill            VARCHAR2(3),
    user_form_template_guid VARCHAR2(36),
    start_date              DATE         NOT NULL,
    end_date                DATE,
    cpd_start_date          DATE         NOT NULL,
    cpd_end_date            DATE         NOT NULL,
    rec_ent_date            DATE         NOT NULL,
    rec_ent_user            VARCHAR2(36) NOT NULL,
    rec_mod_date            DATE,
    rec_mod_user            VARCHAR2(36),
    CONSTRAINT pk_pfc PRIMARY KEY (pfc_guid),
    CONSTRAINT fk_pfc_payor FOREIGN KEY (payor_guid)
        REFERENCES payors (payor_guid)
);

CREATE TABLE linking_form_lu (
    billing_form_code   VARCHAR2(10)   NOT NULL,
    phys_form_field_num VARCHAR2(6)    NOT NULL,
    line_num            NUMBER(5)      NOT NULL,
    loop_id             VARCHAR2(20)   NOT NULL,
    field_name          VARCHAR2(50)   NOT NULL,
    field_number        VARCHAR2(10)   NOT NULL,
    record_type_code    VARCHAR2(20)   NOT NULL,
    order_num           NUMBER(5)      NOT NULL,
    mandatory_ind       VARCHAR2(1)    NOT NULL,
    dependency_loop     VARCHAR2(50),
    field_name_desc     VARCHAR2(2000)
);

CREATE TABLE hcfa_electronic_records (
    electronic_rec_guid         VARCHAR2(36) NOT NULL,
    loop_id                     VARCHAR2(20),
    contiguity_ind              VARCHAR2(1),
    billing_form_code           VARCHAR2(10) NOT NULL,
    record_name                 VARCHAR2(50) NOT NULL,
    record_type_code            VARCHAR2(20) NOT NULL,
    record_size                 NUMBER(5)    NOT NULL,
    mandatory_ind               VARCHAR2(1),
    req_for_claim_ind           VARCHAR2(1),
    payor_type_guid             VARCHAR2(36),
    payor_guid                  VARCHAR2(36),
    plan_guid                   VARCHAR2(36),
    type_of_bill                VARCHAR2(3),
    detail_ind                  VARCHAR2(1) NOT NULL,
    max_number                  VARCHAR2(5),
    invoice_ind                 VARCHAR2(1),
    form_template_guid          VARCHAR2(36),
    carry_forward_ind           VARCHAR2(1),
    max_carry_forward           NUMBER(5),
    sto_proc_name               VARCHAR2(30),
    user_form_template_guid     VARCHAR2(36),
    notes                       VARCHAR2(2000),
    rec_ent_date                DATE         NOT NULL,
    rec_ent_user                VARCHAR2(36) NOT NULL,
    rec_mod_date                DATE,
    rec_mod_user                VARCHAR2(36),
    include_record_data_onclaim CHAR(1) DEFAULT 'Y',
    CONSTRAINT pk_hcfa_electronic_records
        PRIMARY KEY (electronic_rec_guid)
);

CREATE TABLE hcfa_electronic_fields (
    field_number                VARCHAR2(10)  NOT NULL,
    electronic_rec_guid         VARCHAR2(36)  NOT NULL,
    field_name                  VARCHAR2(50)  NOT NULL,
    record_type_code            VARCHAR2(20)  NOT NULL,
    sto_proc_name               VARCHAR2(30),
    pic                         VARCHAR2(50)  NOT NULL,
    field_spec                  VARCHAR2(1),
    position_from               NUMBER(5)     NOT NULL,
    position_thru               NUMBER(5)     NOT NULL,
    field_name_desc             VARCHAR2(2000),
    mandatory_ind               VARCHAR2(1),
    must_fit_length_ind         VARCHAR2(1),
    order_num                   NUMBER(3),
    repeats                     NUMBER,
    detail_ind                  VARCHAR2(1)    NOT NULL,
    occurs_next                 VARCHAR2(10),
    hard_coded_data             VARCHAR2(128),
    field_format                VARCHAR2(128),
    caps_ind                    VARCHAR2(1),
    required_subelement_ind     VARCHAR2(1),
    rec_ent_date                DATE           NOT NULL,
    rec_ent_user                VARCHAR2(36)   NOT NULL,
    rec_mod_date                DATE,
    rec_mod_user                VARCHAR2(36),
    include_data_onclaim        CHAR(1) DEFAULT 'Y',
    CONSTRAINT fk_hef_her FOREIGN KEY (electronic_rec_guid)
        REFERENCES hcfa_electronic_records (electronic_rec_guid)
);
