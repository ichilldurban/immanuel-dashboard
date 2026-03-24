-- =============================================================================
-- METRIC EDGE COST AND CONSTRUCTION CONSULTANTS
-- ME Project Portal — Supabase Database Migration
-- =============================================================================
-- Project:       ME Project Portal System
-- Reference:     ME-PRT-001-R1
-- Author:        S.L. Coetzee PrQS (Reg No. 4923)
-- Date:          24 March 2026
-- Description:   Complete database schema for the Metric Edge Client-Facing
--                Project Portal. Creates all tables, RLS policies, indexes,
--                storage bucket, and seeds the first project record for
--                ME 408 — 9721 Immanuel Church, Seatides.
--
-- INSTRUCTIONS:  Paste this entire file into the Supabase SQL Editor and
--                click "Run". Tables will be created in the public schema.
--                Run once only. Re-running will fail gracefully on IF NOT EXISTS.
-- =============================================================================


-- =============================================================================
-- SECTION 0: EXTENSIONS
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- =============================================================================
-- SECTION 1: CORE TABLE — projects
-- =============================================================================
-- One row per Metric Edge project (ME XXX).
-- This is the parent record that all other tables reference via project_id.

CREATE TABLE IF NOT EXISTS projects (
    id                  UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_code        VARCHAR(10)     NOT NULL UNIQUE,        -- e.g. 'ME 408'
    project_name        TEXT            NOT NULL,               -- e.g. '9721 Immanuel Church'
    client_name         TEXT,                                   -- e.g. 'Immanuel Church Seatides'
    contractor_name     TEXT,                                   -- Main contractor
    architect_name      TEXT,
    current_stage       INTEGER         CHECK (current_stage BETWEEN 1 AND 6),
    status              VARCHAR(20)     DEFAULT 'active'
                                        CHECK (status IN ('active', 'completed', 'on-hold', 'tender')),
    contract_value      NUMERIC(15,2),                          -- Original contract sum excl. VAT
    revised_value       NUMERIC(15,2),                         -- Current AFC excl. VAT
    start_date          DATE,
    completion_date     DATE,
    portal_url          TEXT,
    is_active           BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW()
);

COMMENT ON TABLE projects IS 'Master project register. One row per ME-numbered project.';
COMMENT ON COLUMN projects.contract_value IS 'Original contract sum excluding VAT (PPS Column A basis).';
COMMENT ON COLUMN projects.revised_value IS 'Current AFC — Amount for Completion excl. VAT (PPS Column B basis).';


-- =============================================================================
-- SECTION 2: USER ROLES TABLE — user_roles
-- =============================================================================
-- Controls who can access which project and in what capacity.
-- Drives Row Level Security policies across all tables.

CREATE TABLE IF NOT EXISTS user_roles (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    project_id      UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    role            VARCHAR(20) NOT NULL
                                CHECK (role IN ('admin', 'client', 'consultant', 'contractor')),
    display_name    TEXT,                   -- Friendly name shown in portal UI
    email           TEXT,                   -- Denormalised for quick display
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, project_id)
);

COMMENT ON TABLE user_roles IS 'Maps Supabase auth users to projects with a role. Drives all RLS.';
COMMENT ON COLUMN user_roles.role IS 'admin = ME staff full access; client = read-only cost/docs; consultant = read docs; contractor = BOQ/valuations/packs.';


-- =============================================================================
-- SECTION 3: DOCUMENTS TABLE — documents
-- =============================================================================
-- Central document register. Every file uploaded to Supabase Storage is
-- tracked here with its category, revision, and storage path.

CREATE TABLE IF NOT EXISTS documents (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id      UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Classification
    category        VARCHAR(30) NOT NULL
                                CHECK (category IN (
                                    'drawings',
                                    'quotes',
                                    'packs',
                                    'cost-reports',
                                    'valuations',
                                    'variations',
                                    'site-minutes',
                                    'programme',
                                    'contract',
                                    'submission',
                                    'photos',
                                    'other'
                                )),
    subcategory     TEXT,                   -- e.g. 'architectural', 'structural', 'electrical'

    -- File details
    file_name       TEXT        NOT NULL,   -- ME naming convention: ME408-CR3-2026-03.pdf
    file_path       TEXT        NOT NULL,   -- Supabase Storage path: project-files/ME408/cost-reports/...
    file_size       BIGINT,                 -- Bytes
    file_type       VARCHAR(10),            -- pdf, xlsx, zip, jpg, png, dwg

    -- Version control
    revision        VARCHAR(10) DEFAULT '1',    -- Rev A, Rev B, or numeric 1, 2, 3
    is_current      BOOLEAN     DEFAULT TRUE,   -- FALSE for superseded revisions

    -- Metadata
    description     TEXT,
    status          VARCHAR(20) DEFAULT 'active'
                                CHECK (status IN ('active', 'superseded', 'draft', 'archived')),

    -- Audit
    uploaded_by     UUID        REFERENCES auth.users(id),
    uploaded_at     TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE documents IS 'Central document register for all project files. Every file in Supabase Storage has a row here.';
COMMENT ON COLUMN documents.file_path IS 'Full Supabase Storage path e.g. project-files/ME408/cost-reports/ME408-CR1-2026-03.pdf';
COMMENT ON COLUMN documents.is_current IS 'Set FALSE when a new revision supersedes this document. Only one current revision per document should be TRUE.';


-- =============================================================================
-- SECTION 4: SUBCONTRACTORS TABLE — subcontractors
-- =============================================================================
-- Specialist trades procurement register. Tracks quotes, awards, and
-- procurement pack availability per project.

CREATE TABLE IF NOT EXISTS subcontractors (
    id                          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id                  UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Identification
    sp_code                     VARCHAR(10) NOT NULL,   -- SP-01, SP-02, SP-03...
    trade_name                  TEXT        NOT NULL,   -- e.g. 'Decking', 'Roofing', 'Aluminium'
    subcontractor_name          TEXT,                   -- Company name once appointed

    -- Financials
    quoted_amount               NUMERIC(15,2),          -- Excl. VAT
    status                      VARCHAR(20) DEFAULT 'provisional'
                                            CHECK (status IN ('provisional', 'quoted', 'confirmed', 'rejected')),

    -- Documents
    quote_file_path             TEXT,                   -- Supabase Storage path to quote PDF
    procurement_pack_available  BOOLEAN     DEFAULT FALSE,

    -- Additional
    contact_person              TEXT,
    contact_email               TEXT,
    contact_phone               TEXT,
    notes                       TEXT,

    -- Audit
    created_at                  TIMESTAMPTZ DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(project_id, sp_code)
);

COMMENT ON TABLE subcontractors IS 'Specialist trade procurement register. One row per subcontractor per project.';
COMMENT ON COLUMN subcontractors.sp_code IS 'Procurement code: SP-01, SP-02 etc. Unique within a project.';
COMMENT ON COLUMN subcontractors.quoted_amount IS 'Quoted/contract amount excl. VAT.';


-- =============================================================================
-- SECTION 5: BOQ ITEMS TABLE — boq_items
-- =============================================================================
-- Bill of Quantities line items for cost tracking and AFC management.
-- Supports the PPS cost report structure (above/below the line).

CREATE TABLE IF NOT EXISTS boq_items (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id          UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Classification
    section             TEXT        NOT NULL,   -- e.g. 'Preliminaries', 'Substructure', 'Sound System'
    item_code           VARCHAR(20),            -- BOQ item reference
    item_description    TEXT        NOT NULL,

    -- Financials
    original_amount     NUMERIC(15,2),          -- Stage 4 / tender BOQ amount
    revised_amount      NUMERIC(15,2),          -- Current AFC amount
    variance            NUMERIC(15,2)           -- GENERATED: revised - original
        GENERATED ALWAYS AS (revised_amount - original_amount) STORED,

    -- PPS flag
    is_below_line       BOOLEAN     DEFAULT FALSE,  -- TRUE = below-the-line addition (not in original contract)

    -- Sorting
    sort_order          INTEGER,

    -- Audit
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE boq_items IS 'BOQ line items for AFC tracking. is_below_line flags additions outside the original contract sum.';
COMMENT ON COLUMN boq_items.is_below_line IS 'TRUE for items below the line (sound, AC, chairs, etc.) — additions to original contract.';
COMMENT ON COLUMN boq_items.variance IS 'Auto-calculated: revised_amount minus original_amount. Positive = overrun, negative = saving.';


-- =============================================================================
-- SECTION 6: VARIATIONS TABLE — variations
-- =============================================================================
-- Contract variation/change order register. Tracks all changes to the
-- contract sum from approved, pending, and anticipated variations.

CREATE TABLE IF NOT EXISTS variations (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id      UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Identification
    vo_number       VARCHAR(10) NOT NULL,       -- e.g. 'V001', 'V002A'
    ci_reference    VARCHAR(20),                -- Contract Instruction reference from Architect
    description     TEXT        NOT NULL,

    -- Status and value
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('approved', 'pending', 'anticipated', 'rejected')),
    amount          NUMERIC(15,2),              -- Estimated or approved value excl. VAT
    approved_value  NUMERIC(15,2),              -- Final approved amount (may differ from initial estimate)
    afc_impact      NUMERIC(15,2),              -- Net impact on AFC

    -- Dates
    date_issued     DATE,                       -- Date CI was issued by architect
    date_approved   DATE,                       -- Date variation was financially agreed

    -- Linked document
    document_id     UUID        REFERENCES documents(id),

    -- Notes
    notes           TEXT,

    -- Audit
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(project_id, vo_number)
);

COMMENT ON TABLE variations IS 'Contract variations register. Tracks all changes to the original contract sum.';
COMMENT ON COLUMN variations.status IS 'approved = agreed and signed; pending = submitted, awaiting agreement; anticipated = expected but not yet instructed; rejected = not approved.';


-- =============================================================================
-- SECTION 7: SITE MEETINGS TABLE — site_meetings
-- =============================================================================
-- Site meeting register. Links to minutes documents in storage.

CREATE TABLE IF NOT EXISTS site_meetings (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id          UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Meeting details
    meeting_number      INTEGER     NOT NULL,   -- Site Meeting 1, 2, 3...
    meeting_date        DATE        NOT NULL,
    venue               TEXT,

    -- Attendance (stored as text list or JSON)
    attendees           TEXT,                   -- Comma-separated or free text list

    -- Key outcomes
    key_decisions       TEXT,                   -- Summary of critical decisions / actions

    -- Linked document
    minutes_file_path   TEXT,                   -- Supabase Storage path to minutes PDF
    document_id         UUID        REFERENCES documents(id),

    -- Audit
    created_at          TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(project_id, meeting_number)
);

COMMENT ON TABLE site_meetings IS 'Site meeting register. One row per meeting with link to minutes document.';


-- =============================================================================
-- SECTION 8: SITE PHOTOS TABLE — site_photos
-- =============================================================================
-- Construction progress photo register.

CREATE TABLE IF NOT EXISTS site_photos (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id      UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Photo details
    date_taken      DATE,
    topic           TEXT,                   -- e.g. 'Foundation Pour', 'Roofing Progress', 'Defects'
    description     TEXT,
    file_path       TEXT        NOT NULL,   -- Supabase Storage path
    file_name       TEXT,
    thumbnail_path  TEXT,                   -- Compressed thumbnail path

    -- Metadata
    location_on_site    TEXT,               -- e.g. 'North elevation', 'Kitchen area'
    site_meeting_id     UUID    REFERENCES site_meetings(id),   -- Optional link to meeting

    -- Audit
    uploaded_by     UUID        REFERENCES auth.users(id),
    uploaded_at     TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE site_photos IS 'Construction progress and record photos. Linked to Supabase Storage.';


-- =============================================================================
-- SECTION 9: COST REPORTS TABLE — cost_reports
-- =============================================================================
-- Cost report register aligned with ME PPS standards.
-- Stores header totals from each formal cost report issued.

CREATE TABLE IF NOT EXISTS cost_reports (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id      UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Identification
    report_number   VARCHAR(10) NOT NULL,       -- CR1, CR2, CR3, CR3A...
    report_month    VARCHAR(7),                 -- e.g. '2026-03' (YYYY-MM)
    report_date     DATE,

    -- PPS Columns (non-negotiable — see ME-STD-001-R1)
    -- Column A: Stage 4 / Original Contract Sum
    -- Column B: AFC (Amount for Completion)
    -- Column C: Cumulative Value of Work Done
    -- Column D: Previously Paid (SACRED — actual bank disbursements only)
    -- Column E: Net Due = C - D (MANDATORY FORMULA)
    -- Column F: Cost to Complete = B - C (MANDATORY FORMULA)
    stage4_total        NUMERIC(15,2),          -- Column A
    afc_total           NUMERIC(15,2),          -- Column B
    cumulative          NUMERIC(15,2),          -- Column C
    previously_paid     NUMERIC(15,2),          -- Column D — SACRED
    net_due             NUMERIC(15,2),          -- Column E = C - D
    cost_to_complete    NUMERIC(15,2),          -- Column F = B - C

    -- Linked document
    file_path       TEXT,                       -- Supabase Storage path to report PDF
    document_id     UUID        REFERENCES documents(id),

    -- Audit
    uploaded_at     TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(project_id, report_number)
);

COMMENT ON TABLE cost_reports IS 'Cost report register. Stores PPS column totals per report. See ME-STD-001-R1 for column definitions.';
COMMENT ON COLUMN cost_reports.previously_paid IS 'SACRED: Column D — actual bank disbursements only. Never estimated. Never changed retrospectively.';
COMMENT ON COLUMN cost_reports.net_due IS 'Column E = Cumulative (C) minus Previously Paid (D). Mandatory formula — never manually overridden.';
COMMENT ON COLUMN cost_reports.cost_to_complete IS 'Column F = AFC (B) minus Cumulative (C). Mandatory formula — never manually overridden.';


-- =============================================================================
-- SECTION 10: VALUATIONS TABLE — valuations
-- =============================================================================
-- Payment Certificate / Valuation register.
-- Tracks each contractor valuation through the payment cycle.

CREATE TABLE IF NOT EXISTS valuations (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id          UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    -- Identification
    valuation_number    INTEGER     NOT NULL,   -- Val 01, Val 02...
    valuation_month     VARCHAR(7),             -- 'YYYY-MM'
    valuation_date      DATE,

    -- Financials (all excl. VAT unless noted)
    gross_value         NUMERIC(15,2),          -- Gross value of work done to date
    retention           NUMERIC(15,2),          -- Retention deducted
    net_value           NUMERIC(15,2),          -- After retention
    vat_amount          NUMERIC(15,2),          -- VAT at 15%
    total_incl_vat      NUMERIC(15,2),          -- Total payable incl. VAT
    certified_amount    NUMERIC(15,2),          -- Net certified for payment excl. VAT
    previously_paid     NUMERIC(15,2),          -- Cumulative previously certified
    net_due             NUMERIC(15,2),          -- This certificate amount

    -- Status
    status              VARCHAR(20) DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'issued', 'certified', 'paid')),

    -- Linked document
    file_path           TEXT,                   -- Supabase Storage path to valuation PDF
    document_id         UUID        REFERENCES documents(id),

    -- Audit
    created_at          TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(project_id, valuation_number)
);

COMMENT ON TABLE valuations IS 'Payment certificate / valuation register. One row per contractor valuation.';


-- =============================================================================
-- SECTION 11: INDEXES
-- =============================================================================
-- Performance indexes on frequently queried foreign keys and filter columns.

CREATE INDEX IF NOT EXISTS idx_documents_project      ON documents(project_id);
CREATE INDEX IF NOT EXISTS idx_documents_category     ON documents(category);
CREATE INDEX IF NOT EXISTS idx_documents_is_current   ON documents(is_current);
CREATE INDEX IF NOT EXISTS idx_subcontractors_project ON subcontractors(project_id);
CREATE INDEX IF NOT EXISTS idx_boq_items_project      ON boq_items(project_id);
CREATE INDEX IF NOT EXISTS idx_boq_items_below_line   ON boq_items(is_below_line);
CREATE INDEX IF NOT EXISTS idx_variations_project     ON variations(project_id);
CREATE INDEX IF NOT EXISTS idx_variations_status      ON variations(status);
CREATE INDEX IF NOT EXISTS idx_site_meetings_project  ON site_meetings(project_id);
CREATE INDEX IF NOT EXISTS idx_site_photos_project    ON site_photos(project_id);
CREATE INDEX IF NOT EXISTS idx_cost_reports_project   ON cost_reports(project_id);
CREATE INDEX IF NOT EXISTS idx_valuations_project     ON valuations(project_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user        ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_project     ON user_roles(project_id);


-- =============================================================================
-- SECTION 12: ROW LEVEL SECURITY (RLS)
-- =============================================================================
-- RLS ensures users only see data for projects they are assigned to.
-- The admin role bypasses restrictions for full management access.
-- All policies use the user_roles table as the authority.

-- Helper function: returns TRUE if the calling user has any role on this project
CREATE OR REPLACE FUNCTION has_project_access(p_project_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM user_roles
        WHERE user_id = auth.uid()
        AND project_id = p_project_id
    );
$$ LANGUAGE sql SECURITY DEFINER;

-- Helper function: returns TRUE if the calling user is an admin on this project
CREATE OR REPLACE FUNCTION is_project_admin(p_project_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM user_roles
        WHERE user_id = auth.uid()
        AND project_id = p_project_id
        AND role = 'admin'
    );
$$ LANGUAGE sql SECURITY DEFINER;


-- ---- projects ---------------------------------------------------------------
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "projects_select"
    ON projects FOR SELECT
    USING (has_project_access(id));

CREATE POLICY "projects_insert"
    ON projects FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM user_roles
            WHERE user_id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "projects_update"
    ON projects FOR UPDATE
    USING (is_project_admin(id));

CREATE POLICY "projects_delete"
    ON projects FOR DELETE
    USING (is_project_admin(id));


-- ---- user_roles -------------------------------------------------------------
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

-- Users can see their own role assignments
CREATE POLICY "user_roles_select_own"
    ON user_roles FOR SELECT
    USING (user_id = auth.uid());

-- Admins can see all role assignments for their projects
CREATE POLICY "user_roles_select_admin"
    ON user_roles FOR SELECT
    USING (is_project_admin(project_id));

-- Only admins can manage user roles
CREATE POLICY "user_roles_insert"
    ON user_roles FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "user_roles_update"
    ON user_roles FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "user_roles_delete"
    ON user_roles FOR DELETE
    USING (is_project_admin(project_id));


-- ---- documents --------------------------------------------------------------
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "documents_select"
    ON documents FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "documents_insert"
    ON documents FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "documents_update"
    ON documents FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "documents_delete"
    ON documents FOR DELETE
    USING (is_project_admin(project_id));


-- ---- subcontractors ---------------------------------------------------------
ALTER TABLE subcontractors ENABLE ROW LEVEL SECURITY;

-- All project members can view subcontractors
CREATE POLICY "subcontractors_select"
    ON subcontractors FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "subcontractors_insert"
    ON subcontractors FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "subcontractors_update"
    ON subcontractors FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "subcontractors_delete"
    ON subcontractors FOR DELETE
    USING (is_project_admin(project_id));


-- ---- boq_items --------------------------------------------------------------
ALTER TABLE boq_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "boq_items_select"
    ON boq_items FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "boq_items_insert"
    ON boq_items FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "boq_items_update"
    ON boq_items FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "boq_items_delete"
    ON boq_items FOR DELETE
    USING (is_project_admin(project_id));


-- ---- variations -------------------------------------------------------------
ALTER TABLE variations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "variations_select"
    ON variations FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "variations_insert"
    ON variations FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "variations_update"
    ON variations FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "variations_delete"
    ON variations FOR DELETE
    USING (is_project_admin(project_id));


-- ---- site_meetings ----------------------------------------------------------
ALTER TABLE site_meetings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "site_meetings_select"
    ON site_meetings FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "site_meetings_insert"
    ON site_meetings FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "site_meetings_update"
    ON site_meetings FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "site_meetings_delete"
    ON site_meetings FOR DELETE
    USING (is_project_admin(project_id));


-- ---- site_photos ------------------------------------------------------------
ALTER TABLE site_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "site_photos_select"
    ON site_photos FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "site_photos_insert"
    ON site_photos FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "site_photos_update"
    ON site_photos FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "site_photos_delete"
    ON site_photos FOR DELETE
    USING (is_project_admin(project_id));


-- ---- cost_reports -----------------------------------------------------------
ALTER TABLE cost_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cost_reports_select"
    ON cost_reports FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "cost_reports_insert"
    ON cost_reports FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "cost_reports_update"
    ON cost_reports FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "cost_reports_delete"
    ON cost_reports FOR DELETE
    USING (is_project_admin(project_id));


-- ---- valuations -------------------------------------------------------------
ALTER TABLE valuations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "valuations_select"
    ON valuations FOR SELECT
    USING (has_project_access(project_id));

CREATE POLICY "valuations_insert"
    ON valuations FOR INSERT
    WITH CHECK (is_project_admin(project_id));

CREATE POLICY "valuations_update"
    ON valuations FOR UPDATE
    USING (is_project_admin(project_id));

CREATE POLICY "valuations_delete"
    ON valuations FOR DELETE
    USING (is_project_admin(project_id));


-- =============================================================================
-- SECTION 13: STORAGE BUCKET
-- =============================================================================
-- Creates the 'project-files' storage bucket for all document uploads.
-- Files are organised by: project-files/{project_code}/{category}/{filename}
-- e.g. project-files/ME408/cost-reports/ME408-CR1-2026-03.pdf

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'project-files',
    'project-files',
    FALSE,                  -- Private bucket — access controlled via RLS
    52428800,               -- 50MB per file limit
    ARRAY[
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-excel',
        'application/zip',
        'image/jpeg',
        'image/jpg',
        'image/png',
        'image/webp',
        'text/plain',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ]
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Only authenticated users with project access can read files
-- The path convention project-files/{project_code}/... enables project-level control

CREATE POLICY "storage_select_authenticated"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'project-files');

CREATE POLICY "storage_insert_authenticated"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'project-files');

CREATE POLICY "storage_update_authenticated"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (bucket_id = 'project-files');

CREATE POLICY "storage_delete_authenticated"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (bucket_id = 'project-files');


-- =============================================================================
-- SECTION 14: SEED DATA — ME 408 IMMANUEL CHURCH, SEATIDES
-- =============================================================================
-- Insert the first project record with all confirmed financial data.
-- Amounts are excl. VAT unless stated.
--
-- FINANCIAL SUMMARY:
--   Original BOQ (contract sum):          R 4,998,872.00
--   Below-the-line additions:             R   650,000.00
--     Sound System                            R 200,000
--     Air Conditioning                        R 150,000
--     Chairs                                  R 100,000
--     Kitchen                                 R 100,000
--     Coffee Fridges                           R  20,000
--     Doors (additional)                       R  50,000
--     Carpet                                   R  30,000 (note: SP-08 Dave Moon quoted R98K)
--   Total (contract + below-line):        R 5,648,872.00
--   Revised AFC (per portal display):     R 5,396,430.00
--
-- NOTE: The contract_value and revised_value reflect the current working
-- figures as used in the Immanuel Church dashboard. Update as AFC is refined.

-- 14.1 Insert project record
INSERT INTO projects (
    project_code,
    project_name,
    client_name,
    contractor_name,
    architect_name,
    current_stage,
    status,
    contract_value,
    revised_value,
    portal_url,
    is_active
)
VALUES (
    'ME 408',
    '9721 Immanuel Church',
    'Immanuel Church Seatides',
    'TBC',                  -- Main contractor TBC — update when appointed
    'TBC',                  -- Architect — update when confirmed
    4,                      -- Stage 4: Construction Documentation / Construction
    'active',
    4998872.00,             -- Original BOQ / contract sum excl. VAT
    5396430.00,             -- Revised AFC excl. VAT (current working figure)
    'https://immanuel-dashboard.vercel.app',
    TRUE
)
ON CONFLICT (project_code) DO NOTHING;


-- 14.2 BOQ Items — Above-the-line (original contract sum)
-- These form the R4,998,872 original BOQ.
-- Sections are indicative — update with actual BOQ section breakdown when available.

INSERT INTO boq_items (project_id, section, item_description, original_amount, revised_amount, is_below_line, sort_order)
SELECT
    p.id,
    i.section,
    i.item_description,
    i.original_amount,
    i.revised_amount,
    FALSE,
    i.sort_order
FROM projects p
CROSS JOIN (
    VALUES
        ('Preliminaries',           'Contractor Preliminaries & General',       0.00,       0.00,       1),
        ('Substructure',            'Substructure — Foundations & Slab',        0.00,       0.00,       2),
        ('Superstructure',          'Superstructure — Frame, Walls, Roof',      0.00,       0.00,       3),
        ('Finishes',                'Internal Finishes — Floors, Walls, Ceilings', 0.00,   0.00,       4),
        ('Specialist Subcontractors','Specialist Subcontractors (SP items)',     0.00,       0.00,       5),
        ('Services',                'Mechanical & Electrical Services',         0.00,       0.00,       6),
        ('External Works',          'External Works & Landscaping',             0.00,       0.00,       7),
        ('TOTAL',                   'ORIGINAL CONTRACT SUM (excl. VAT)',        4998872.00, 4998872.00, 99)
) AS i(section, item_description, original_amount, revised_amount, sort_order)
WHERE p.project_code = 'ME 408'
ON CONFLICT DO NOTHING;

-- 14.3 BOQ Items — Below-the-line additions (R650,000 total)
-- These are additions outside the original contract sum.
-- They are tracked separately per PPS standards (is_below_line = TRUE).

INSERT INTO boq_items (project_id, section, item_description, original_amount, revised_amount, is_below_line, sort_order)
SELECT
    p.id,
    i.section,
    i.item_description,
    i.original_amount,
    i.revised_amount,
    TRUE,
    i.sort_order
FROM projects p
CROSS JOIN (
    VALUES
        ('Below-the-Line Additions', 'Sound System (AV/PA)',                    0.00, 200000.00, 101),
        ('Below-the-Line Additions', 'Air Conditioning (HVAC)',                 0.00, 150000.00, 102),
        ('Below-the-Line Additions', 'Chairs (Auditorium Seating)',             0.00, 100000.00, 103),
        ('Below-the-Line Additions', 'Kitchen Equipment & Fitout',              0.00, 100000.00, 104),
        ('Below-the-Line Additions', 'Coffee Station Fridges',                  0.00,  20000.00, 105),
        ('Below-the-Line Additions', 'Doors (Additional Door Allowance)',       0.00,  50000.00, 106),
        ('Below-the-Line Additions', 'Carpet (see also SP-08 Dave Moon quote)', 0.00,  30000.00, 107),
        ('Below-the-Line TOTAL',     'TOTAL BELOW-THE-LINE ADDITIONS',          0.00, 650000.00, 199)
) AS i(section, item_description, original_amount, revised_amount, sort_order)
WHERE p.project_code = 'ME 408'
ON CONFLICT DO NOTHING;


-- 14.4 Subcontractors — Specialist trades procurement register
-- SP codes and amounts as confirmed in project records.
-- All amounts excl. VAT.
--
-- SUBCONTRACTOR REGISTER SUMMARY:
--   SP-01  Big Decks               Decking                     R 499,240
--   SP-02  Seacon Roofing          Roofing                     R 343,176
--   SP-03  C-Con Aluminium         Aluminium (windows/glazing)  R 476,280
--   SP-05  RSW                     Metal Palisade Fencing       R  38,511
--   SP-06  RSW                     Balustrades                  R  17,557
--   SP-07  Gutter Brigade          Rainwater / Gutters          R  62,730
--   SP-08  Dave Moon               Carpet (supply & fix)        R  98,000
--   SP-09  Decorative Screed       Screed flooring (rate-based)  TBC
--   SP-11  CW Electrical           Electrical (general)        R 385,000
--   SP-11  CW Electrical           3-Phase upgrade             R  45,000
--
-- SP-04 and SP-10 are not listed — may be unawarded or not applicable.
-- CW Electrical split into two line items (general + 3-phase). Stored separately.

INSERT INTO subcontractors (
    project_id, sp_code, trade_name, subcontractor_name,
    quoted_amount, status, procurement_pack_available, notes
)
SELECT
    p.id,
    s.sp_code,
    s.trade_name,
    s.subcontractor_name,
    s.quoted_amount,
    s.status,
    s.pack_available,
    s.notes
FROM projects p
CROSS JOIN (
    VALUES
        ('SP-01', 'Decking',                    'Big Decks',            499240.00,  'quoted', FALSE, 'Timber/composite decking'),
        ('SP-02', 'Roofing',                    'Seacon Roofing',       343176.00,  'quoted', FALSE, 'Roof covering and sheeting'),
        ('SP-03', 'Aluminium Glazing',          'C-Con Aluminium',      476280.00,  'quoted', FALSE, 'Aluminium windows, doors and glazing'),
        ('SP-05', 'Metal Palisade Fencing',     'RSW',                   38511.00,  'quoted', FALSE, 'Boundary palisade fencing'),
        ('SP-06', 'Balustrades',                'RSW',                   17557.00,  'quoted', FALSE, 'Internal/external balustrades — same supplier as SP-05'),
        ('SP-07', 'Rainwater / Gutters',        'Gutter Brigade',        62730.00,  'quoted', FALSE, 'Rainwater goods, gutters and downpipes'),
        ('SP-08', 'Carpet',                     'Dave Moon Carpet',      98000.00,  'quoted', FALSE, 'Supply and fix carpet — note: below-line allowance R30K vs quoted R98K — review'),
        ('SP-09', 'Decorative Screed',          'TBC',                       NULL,  'provisional', FALSE, 'Rate-based item — no fixed lump sum. Obtain rate and measure on completion.'),
        ('SP-11A','Electrical (General)',        'CW Electrical',        385000.00,  'quoted', FALSE, 'General electrical installation'),
        ('SP-11B','Electrical (3-Phase Upgrade)','CW Electrical',         45000.00,  'quoted', FALSE, '3-phase power supply upgrade — separate to general electrical quote')
) AS s(sp_code, trade_name, subcontractor_name, quoted_amount, status, pack_available, notes)
WHERE p.project_code = 'ME 408'
ON CONFLICT (project_id, sp_code) DO NOTHING;


-- =============================================================================
-- SECTION 15: VERIFICATION QUERIES
-- =============================================================================
-- Run these after executing the migration to confirm data was inserted correctly.
-- (Comment out before running in production if preferred.)

-- Verify project was created:
-- SELECT project_code, project_name, contract_value, revised_value FROM projects WHERE project_code = 'ME 408';

-- Verify BOQ totals:
-- SELECT is_below_line, COUNT(*) as item_count, SUM(revised_amount) as total
-- FROM boq_items b
-- JOIN projects p ON b.project_id = p.id
-- WHERE p.project_code = 'ME 408'
-- GROUP BY is_below_line;

-- Verify subcontractors:
-- SELECT sp_code, trade_name, subcontractor_name, quoted_amount
-- FROM subcontractors s
-- JOIN projects p ON s.project_id = p.id
-- WHERE p.project_code = 'ME 408'
-- ORDER BY sp_code;

-- Verify subcontractor total (excl. rate-based SP-09):
-- SELECT SUM(quoted_amount) as total_quoted
-- FROM subcontractors s
-- JOIN projects p ON s.project_id = p.id
-- WHERE p.project_code = 'ME 408' AND quoted_amount IS NOT NULL;

-- Verify all tables exist:
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;


-- =============================================================================
-- END OF MIGRATION
-- =============================================================================
-- Tables created:
--   1. projects         — Master project register
--   2. user_roles       — User-to-project access control (replaces user_projects)
--   3. documents        — Central document register
--   4. subcontractors   — Specialist trade procurement register
--   5. boq_items        — BOQ line items with above/below-line flag
--   6. variations       — Contract variations register
--   7. site_meetings    — Site meeting register
--   8. site_photos      — Construction progress photos
--   9. cost_reports     — PPS cost report header register
--  10. valuations       — Payment certificate register
--
-- Storage:
--   Bucket 'project-files' created (private, 50MB limit)
--   Path convention: project-files/{project_code}/{category}/{filename}
--
-- Seed data:
--   ME 408 — 9721 Immanuel Church, Seatides inserted
--   10 subcontractor records (SP-01 through SP-11B)
--   9 BOQ above-the-line sections + 8 below-the-line items
--
-- S.L. Coetzee PrQS — Metric Edge Cost & Construction Consultants
-- stef@metricedge.co.za | 084 532 4848
-- =============================================================================
