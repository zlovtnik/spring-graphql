-- Oracle Schema for GraphQL Scala App
-- All business logic implemented in procedures and functions, no triggers used.
--
-- IMPORTANT: Before executing this script, run grant_privileges.sql as SYS/DBA to grant necessary privileges to the application user.

-- Make script idempotent for development

-- Create users table (skip if exists)
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE users (
        id VARCHAR2(36) PRIMARY KEY,
        username VARCHAR2(255) NOT NULL UNIQUE,
        password VARCHAR2(255) NOT NULL,
        email VARCHAR2(255) NOT NULL UNIQUE,
        created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        updated_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
    )';
EXCEPTION
    WHEN OTHERS THEN
-- Types for dynamic CRUD operations (used by dynamic_crud_pkg)
CREATE OR REPLACE TYPE dyn_column_name_nt AS TABLE OF VARCHAR2(128);
/

CREATE OR REPLACE TYPE dyn_column_value_nt AS TABLE OF VARCHAR2(4000);
/

CREATE OR REPLACE TYPE dyn_filter_rec AS OBJECT (
    column_name VARCHAR2(128),
    operator    VARCHAR2(10),
    value       VARCHAR2(4000)
);
/

CREATE OR REPLACE TYPE dyn_filter_nt AS TABLE OF dyn_filter_rec;
/

CREATE OR REPLACE TYPE dyn_row_op_rec AS OBJECT (
    column_names  dyn_column_name_nt,
    column_values dyn_column_value_nt
);
/

CREATE OR REPLACE TYPE dyn_row_op_nt AS TABLE OF dyn_row_op_rec;
/

CREATE OR REPLACE TYPE dyn_audit_ctx_rec AS OBJECT (
    actor     VARCHAR2(128),
    trace_id  VARCHAR2(128),
    client_ip VARCHAR2(45),
    metadata  CLOB
);
/

-- Package specification for dynamic CRUD operations
CREATE OR REPLACE PACKAGE dynamic_crud_pkg AS
    -- Supported operation names
    c_op_create CONSTANT VARCHAR2(10) := 'CREATE';
    c_op_read   CONSTANT VARCHAR2(10) := 'READ';
    c_op_update CONSTANT VARCHAR2(10) := 'UPDATE';
    c_op_delete CONSTANT VARCHAR2(10) := 'DELETE';

    SUBTYPE t_operation IS VARCHAR2(10);

    -- Metadata helpers
    FUNCTION is_table_allowed(p_table_name IN VARCHAR2) RETURN BOOLEAN;
    FUNCTION normalize_table_name(p_table_name IN VARCHAR2) RETURN VARCHAR2;

    -- Execute a single-row CRUD operation
    PROCEDURE execute_operation(
        p_table_name    IN VARCHAR2,
        p_operation     IN t_operation,
        p_column_names  IN dyn_column_name_nt,
        p_column_values IN dyn_column_value_nt,
        p_filters       IN dyn_filter_nt DEFAULT NULL,
        p_audit         IN dyn_audit_ctx_rec DEFAULT NULL,
        p_message       OUT VARCHAR2,
        p_generated_id  OUT VARCHAR2,
        p_affected_rows OUT NUMBER
    );

    -- Execute a bulk CRUD operation using collection payload
    PROCEDURE execute_bulk(
        p_table_name IN VARCHAR2,
        p_operation  IN t_operation,
        p_rows       IN dyn_row_op_nt,
        p_filters    IN dyn_filter_nt DEFAULT NULL,
        p_audit      IN dyn_audit_ctx_rec DEFAULT NULL,
        p_message    OUT VARCHAR2,
        p_affected   OUT NUMBER
    );
END dynamic_crud_pkg;
/

CREATE OR REPLACE PACKAGE BODY dynamic_crud_pkg AS

    TYPE t_allowed_table_nt IS TABLE OF VARCHAR2(128);
    g_allowed_tables CONSTANT t_allowed_table_nt := t_allowed_table_nt(
        'USERS',
        'AUDIT_LOGIN_ATTEMPTS',
        'AUDIT_SESSIONS'
    );

    TYPE t_column_meta_rec IS RECORD (
        data_type VARCHAR2(106),
        nullable  VARCHAR2(1)
    );

    TYPE t_column_meta_tab IS TABLE OF t_column_meta_rec INDEX BY VARCHAR2(128);

    TYPE t_bind_tab IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;

    FUNCTION normalize_identifier(p_value IN VARCHAR2, p_kind IN VARCHAR2) RETURN VARCHAR2 IS
        v_value VARCHAR2(128) := UPPER(TRIM(p_value));
    BEGIN
        IF v_value IS NULL THEN
            RAISE_APPLICATION_ERROR(-20900, 'Missing ' || p_kind);
        END IF;
        IF NOT REGEXP_LIKE(v_value, '^[A-Z][A-Z0-9_$#]{0,127}$') THEN
            RAISE_APPLICATION_ERROR(-20901, 'Invalid ' || p_kind || ' name: ' || p_value);
        END IF;
        RETURN v_value;
    END normalize_identifier;

    PROCEDURE load_column_metadata(
        p_table_name IN VARCHAR2,
        p_columns    OUT t_column_meta_tab
    ) IS
    BEGIN
        p_columns.DELETE;
        FOR rec IN (
            SELECT column_name, data_type, nullable
            FROM   user_tab_columns
            WHERE  table_name = p_table_name
        ) LOOP
            p_columns(rec.column_name) := t_column_meta_rec(rec.data_type, rec.nullable);
        END LOOP;

        IF p_columns.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20902, 'Unknown table: ' || p_table_name);
        END IF;
    END load_column_metadata;

    FUNCTION is_table_allowed(p_table_name IN VARCHAR2) RETURN BOOLEAN IS
        v_table VARCHAR2(128) := normalize_identifier(p_table_name, 'table');
    BEGIN
        FOR i IN g_allowed_tables.FIRST .. g_allowed_tables.LAST LOOP
            IF g_allowed_tables(i) = v_table THEN
                RETURN TRUE;
            END IF;
        END LOOP;
        RETURN FALSE;
    END is_table_allowed;

    FUNCTION normalize_table_name(p_table_name IN VARCHAR2) RETURN VARCHAR2 IS
        v_table VARCHAR2(128) := normalize_identifier(p_table_name, 'table');
    BEGIN
        RETURN v_table;
    END normalize_table_name;

    FUNCTION normalize_operator(p_operator IN VARCHAR2) RETURN VARCHAR2 IS
        v_op VARCHAR2(10) := UPPER(TRIM(p_operator));
    BEGIN
        IF v_op IN ('=', '<>', '!=', '<', '>', '<=', '>=', 'LIKE') THEN
            IF v_op = '!=' THEN
                RETURN '<>';
            END IF;
            RETURN v_op;
        END IF;
        RAISE_APPLICATION_ERROR(-20903, 'Unsupported operator: ' || p_operator);
    END normalize_operator;

    PROCEDURE record_audit(
        p_table_name   IN VARCHAR2,
        p_operation    IN t_operation,
        p_audit        IN dyn_audit_ctx_rec,
        p_status       IN VARCHAR2,
        p_message      IN VARCHAR2,
        p_error_code   IN VARCHAR2,
        p_affected     IN NUMBER
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_actor     VARCHAR2(128);
        v_trace_id  VARCHAR2(128);
        v_client_ip VARCHAR2(45);
        v_metadata  CLOB;
    BEGIN
        IF p_audit IS NOT NULL THEN
            v_actor := p_audit.actor;
            v_trace_id := p_audit.trace_id;
            v_client_ip := p_audit.client_ip;
            v_metadata := p_audit.metadata;
        END IF;

        INSERT INTO audit_dynamic_crud (
            id,
            table_name,
            operation,
            actor,
            trace_id,
            client_ip,
            metadata,
            affected_rows,
            status,
            message,
            error_code,
            created_at
        ) VALUES (
            audit_seq.NEXTVAL,
            p_table_name,
            p_operation,
            v_actor,
            v_trace_id,
            v_client_ip,
            v_metadata,
            p_affected,
            p_status,
            SUBSTR(p_message, 1, 4000),
            p_error_code,
            SYSTIMESTAMP
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END record_audit;

    PROCEDURE validate_columns(
        p_columns_meta IN t_column_meta_tab,
        p_identifiers  IN dyn_column_name_nt,
        p_context      IN VARCHAR2
    ) IS
        v_name VARCHAR2(128);
    BEGIN
        IF p_identifiers IS NULL THEN
            RETURN;
        END IF;

        FOR i IN 1 .. p_identifiers.COUNT LOOP
            v_name := normalize_identifier(p_identifiers(i), p_context || ' column');
            IF NOT p_columns_meta.EXISTS(v_name) THEN
                RAISE_APPLICATION_ERROR(-20904, 'Column ' || v_name || ' not found in table');
            END IF;
        END LOOP;
    END validate_columns;

    PROCEDURE build_where_clause(
        p_filters      IN dyn_filter_nt,
        p_columns_meta IN t_column_meta_tab,
        p_clause       OUT VARCHAR2,
        p_bindings     IN OUT t_bind_tab,
        p_bind_index   IN OUT PLS_INTEGER
    ) IS
        v_parts  VARCHAR2(32767) := '';
        v_name   VARCHAR2(128);
        v_op     VARCHAR2(10);
        v_value  VARCHAR2(4000);
        v_bind   VARCHAR2(20);
    BEGIN
        IF p_filters IS NULL OR p_filters.COUNT = 0 THEN
            p_clause := NULL;
            RETURN;
        END IF;

        FOR i IN 1 .. p_filters.COUNT LOOP
            v_name := normalize_identifier(p_filters(i).column_name, 'filter');
            IF NOT p_columns_meta.EXISTS(v_name) THEN
                RAISE_APPLICATION_ERROR(-20905, 'Filter column ' || v_name || ' not found');
            END IF;
            v_op := normalize_operator(p_filters(i).operator);
            v_value := p_filters(i).value;

            IF i > 1 THEN
                v_parts := v_parts || ' AND ';
            END IF;

            p_bind_index := p_bind_index + 1;
            p_bindings(p_bind_index) := v_value;
            v_bind := ':b' || p_bind_index;

            v_parts := v_parts || '"' || v_name || '" ' || v_op || ' ' || v_bind;
        END LOOP;

        p_clause := ' WHERE ' || v_parts;
    END build_where_clause;

    PROCEDURE bind_values(
        p_cursor     IN INTEGER,
        p_bindings   IN t_bind_tab,
        p_bind_index IN PLS_INTEGER
    ) IS
    BEGIN
        FOR i IN 1 .. p_bind_index LOOP
            DBMS_SQL.BIND_VARIABLE(p_cursor, ':b' || i, p_bindings(i));
        END LOOP;
    END bind_values;

    PROCEDURE execute_dynamic_dml(
        p_sql         IN VARCHAR2,
        p_bindings    IN t_bind_tab,
        p_bind_index  IN PLS_INTEGER,
        p_rows_affected OUT NUMBER
    ) IS
        v_cursor INTEGER;
    BEGIN
        v_cursor := DBMS_SQL.OPEN_CURSOR;
        BEGIN
            DBMS_SQL.PARSE(v_cursor, p_sql, DBMS_SQL.NATIVE);
            bind_values(v_cursor, p_bindings, p_bind_index);
            p_rows_affected := DBMS_SQL.EXECUTE(v_cursor);
        FINALLY
            DBMS_SQL.CLOSE_CURSOR(v_cursor);
        END;
    END execute_dynamic_dml;

    FUNCTION find_value_for_column(
        p_names  IN dyn_column_name_nt,
        p_values IN dyn_column_value_nt,
        p_target IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        IF p_names IS NULL OR p_values IS NULL THEN
            RETURN NULL;
        END IF;
        FOR i IN 1 .. p_names.COUNT LOOP
            IF normalize_identifier(p_names(i), 'column') = p_target THEN
                RETURN p_values(i);
            END IF;
        END LOOP;
        RETURN NULL;
    END find_value_for_column;

    FUNCTION column_list_contains(
        p_names  IN dyn_column_name_nt,
        p_target IN VARCHAR2
    ) RETURN BOOLEAN IS
        v_target VARCHAR2(128) := normalize_identifier(p_target, 'column');
    BEGIN
        IF p_names IS NULL OR p_names.COUNT = 0 THEN
            RETURN FALSE;
        END IF;
        FOR i IN 1 .. p_names.COUNT LOOP
            IF normalize_identifier(p_names(i), 'column') = v_target THEN
                RETURN TRUE;
            END IF;
        END LOOP;
        RETURN FALSE;
    END column_list_contains;

    PROCEDURE execute_operation(
        p_table_name    IN VARCHAR2,
        p_operation     IN t_operation,
        p_column_names  IN dyn_column_name_nt,
        p_column_values IN dyn_column_value_nt,
        p_filters       IN dyn_filter_nt,
        p_audit         IN dyn_audit_ctx_rec,
        p_message       OUT VARCHAR2,
        p_generated_id  OUT VARCHAR2,
        p_affected_rows OUT NUMBER
    ) IS
        v_table_name    VARCHAR2(128);
        v_operation     VARCHAR2(10) := UPPER(TRIM(p_operation));
        v_columns_meta  t_column_meta_tab;
        v_bindings      t_bind_tab;
        v_bind_index    PLS_INTEGER := 0;
        v_sql           VARCHAR2(32767);
        v_set_clause    VARCHAR2(32767);
        v_columns_list  VARCHAR2(32767);
        v_values_list   VARCHAR2(32767);
        v_where_clause  VARCHAR2(32767);
        v_status        VARCHAR2(20) := 'SUCCESS';
        v_error_code    VARCHAR2(50);
    BEGIN
        p_message := NULL;
        p_generated_id := NULL;
        p_affected_rows := 0;

        v_table_name := normalize_table_name(p_table_name);

        IF NOT is_table_allowed(v_table_name) THEN
            RAISE_APPLICATION_ERROR(-20906, 'Table not allowed: ' || v_table_name);
        END IF;

        load_column_metadata(v_table_name, v_columns_meta);

        IF p_column_names IS NOT NULL AND p_column_values IS NOT NULL THEN
            IF p_column_names.COUNT != p_column_values.COUNT THEN
                RAISE_APPLICATION_ERROR(-20907, 'Column names and values count mismatch');
            END IF;
        END IF;

        validate_columns(v_columns_meta, p_column_names, 'payload');

        IF p_filters IS NOT NULL THEN
            NULL; -- validation occurs in build_where_clause
        END IF;

        CASE v_operation
            WHEN c_op_create THEN
                IF p_column_names IS NULL OR p_column_names.COUNT = 0 THEN
                    RAISE_APPLICATION_ERROR(-20908, 'CREATE requires columns');
                END IF;

                FOR i IN 1 .. p_column_names.COUNT LOOP
                    IF i > 1 THEN
                        v_columns_list := v_columns_list || ', ';
                        v_values_list := v_values_list || ', ';
                    END IF;
                    v_columns_list := v_columns_list || '"' || normalize_identifier(p_column_names(i), 'column') || '"';
                    v_bind_index := v_bind_index + 1;
                    v_bindings(v_bind_index) := p_column_values(i);
                    v_values_list := v_values_list || ':b' || v_bind_index;
                END LOOP;

                v_sql := 'INSERT INTO ' || v_table_name || ' (' || v_columns_list || ') VALUES (' || v_values_list || ')';

                execute_dynamic_dml(v_sql, v_bindings, v_bind_index, p_affected_rows);

                IF p_affected_rows = 1 THEN
                    p_generated_id := find_value_for_column(p_column_names, p_column_values, 'ID');
                END IF;
                p_message := 'INSERT SUCCESS';

            WHEN c_op_update THEN
                IF p_column_names IS NULL OR p_column_names.COUNT = 0 THEN
                    RAISE_APPLICATION_ERROR(-20909, 'UPDATE requires columns');
                END IF;

                build_where_clause(p_filters, v_columns_meta, v_where_clause, v_bindings, v_bind_index);
                IF v_where_clause IS NULL THEN
                    RAISE_APPLICATION_ERROR(-20910, 'UPDATE requires filters');
                END IF;

                FOR i IN 1 .. p_column_names.COUNT LOOP
                    IF i > 1 THEN
                        v_set_clause := v_set_clause || ', ';
                    END IF;
                    v_set_clause := v_set_clause || '"' || normalize_identifier(p_column_names(i), 'column') || '" = :b' || (v_bind_index + 1);
                    v_bind_index := v_bind_index + 1;
                    v_bindings(v_bind_index) := p_column_values(i);
                END LOOP;

                IF v_columns_meta.EXISTS('UPDATED_AT') AND NOT column_list_contains(p_column_names, 'UPDATED_AT') THEN
                    IF v_set_clause IS NOT NULL THEN
                        v_set_clause := v_set_clause || ', ';
                    END IF;
                    v_set_clause := v_set_clause || '"UPDATED_AT" = SYSTIMESTAMP';
                END IF;

                v_sql := 'UPDATE ' || v_table_name || ' SET ' || v_set_clause || v_where_clause;

                execute_dynamic_dml(v_sql, v_bindings, v_bind_index, p_affected_rows);
                p_message := 'UPDATE SUCCESS';

            WHEN c_op_delete THEN
                build_where_clause(p_filters, v_columns_meta, v_where_clause, v_bindings, v_bind_index);
                IF v_where_clause IS NULL THEN
                    RAISE_APPLICATION_ERROR(-20911, 'DELETE requires filters');
                END IF;

                v_sql := 'DELETE FROM ' || v_table_name || v_where_clause;
                execute_dynamic_dml(v_sql, v_bindings, v_bind_index, p_affected_rows);
                p_message := 'DELETE SUCCESS';

            WHEN c_op_read THEN
                RAISE_APPLICATION_ERROR(-20912, 'READ operation is not supported in execute_operation');

            ELSE
                RAISE_APPLICATION_ERROR(-20913, 'Unknown operation: ' || v_operation);
        END CASE;

        record_audit(v_table_name, v_operation, p_audit, v_status, p_message, v_error_code, p_affected_rows);

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_error_code := TO_CHAR(SQLCODE);
            p_message := SUBSTR(SQLERRM, 1, 4000);
            record_audit(v_table_name, v_operation, p_audit, v_status, p_message, v_error_code, p_affected_rows);
            RAISE;
    END execute_operation;

    PROCEDURE execute_bulk(
        p_table_name IN VARCHAR2,
        p_operation  IN t_operation,
        p_rows       IN dyn_row_op_nt,
        p_filters    IN dyn_filter_nt,
        p_audit      IN dyn_audit_ctx_rec,
        p_message    OUT VARCHAR2,
        p_affected   OUT NUMBER
    ) IS
        v_total NUMBER := 0;
        v_message VARCHAR2(4000);
        v_generated_id VARCHAR2(4000);
    BEGIN
        IF p_rows IS NULL OR p_rows.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20914, 'Bulk payload is empty');
        END IF;

        FOR i IN 1 .. p_rows.COUNT LOOP
            execute_operation(
                p_table_name,
                p_operation,
                p_rows(i).column_names,
                p_rows(i).column_values,
                CASE WHEN p_operation = c_op_delete OR p_operation = c_op_update THEN p_filters ELSE NULL END,
                p_audit,
                v_message,
                v_generated_id,
                p_affected
            );
            v_total := v_total + NVL(p_affected, 0);
        END LOOP;

        p_message := 'BULK ' || UPPER(p_operation) || ' SUCCESS';
        p_affected := v_total;
    END execute_bulk;

END dynamic_crud_pkg;
/

-- Create package for user operations
CREATE OR REPLACE PACKAGE user_pkg AS
    -- Procedure to create a new user
    PROCEDURE create_user(
        p_username IN VARCHAR2,
        p_password IN VARCHAR2,
        p_email IN VARCHAR2,
        p_user_id OUT VARCHAR2
    );

    -- Function to get user by ID
    FUNCTION get_user_by_id(p_user_id IN VARCHAR2) RETURN SYS_REFCURSOR;

    -- Function to get user by username
    FUNCTION get_user_by_username(p_username IN VARCHAR2) RETURN SYS_REFCURSOR;

    -- Function to get user by email
    FUNCTION get_user_by_email(p_email IN VARCHAR2) RETURN SYS_REFCURSOR;

    -- Procedure to update user
    PROCEDURE update_user(
        p_user_id IN VARCHAR2,
        p_username IN VARCHAR2 DEFAULT NULL,
        p_email IN VARCHAR2 DEFAULT NULL,
        p_password IN VARCHAR2 DEFAULT NULL
    );

    -- Function to delete user and return rows deleted
    FUNCTION delete_user(p_user_id IN VARCHAR2) RETURN NUMBER;

    -- Function to check if username exists
    FUNCTION username_exists(p_username IN VARCHAR2) RETURN BOOLEAN;

    -- Function to check if email exists
    FUNCTION email_exists(p_email IN VARCHAR2) RETURN BOOLEAN;

    -- Procedure to log login attempt
    PROCEDURE log_login_attempt(
        p_username IN VARCHAR2,
        p_success IN NUMBER,
        p_ip_address IN VARCHAR2 DEFAULT NULL,
        p_user_agent IN VARCHAR2 DEFAULT NULL,
        p_failure_reason IN VARCHAR2 DEFAULT NULL
    );

    -- Procedure to log session start
    PROCEDURE log_session_start(
        p_user_id IN VARCHAR2,
        p_token_hash IN VARCHAR2,
        p_ip_address IN VARCHAR2 DEFAULT NULL,
        p_user_agent IN VARCHAR2 DEFAULT NULL
    );
END user_pkg;
/

CREATE OR REPLACE PACKAGE BODY user_pkg AS
    -- Helper function to generate UUID
    FUNCTION generate_uuid RETURN VARCHAR2 IS
        v_uuid RAW(16);
        v_hex VARCHAR2(32);
    BEGIN
        v_uuid := SYS_GUID();
        v_hex := RAWTOHEX(v_uuid);
        RETURN LOWER(SUBSTR(v_hex, 1, 8) || '-' || SUBSTR(v_hex, 9, 4) || '-' || SUBSTR(v_hex, 13, 4) || '-' || SUBSTR(v_hex, 17, 4) || '-' || SUBSTR(v_hex, 21, 12));
    END generate_uuid;

    PROCEDURE create_user(
        p_username IN VARCHAR2,
        p_password IN VARCHAR2,
        p_email IN VARCHAR2,
        p_user_id OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        -- Validate email format
        IF NOT REGEXP_LIKE(p_email, '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$', 'i') THEN
            RAISE_APPLICATION_ERROR(-20005, 'Invalid email format');
        END IF;

        -- Validate password length
        IF LENGTH(p_password) < 8 THEN
            RAISE_APPLICATION_ERROR(-20006, 'Password must be at least 8 characters');
        END IF;

        -- Check if username already exists
        IF username_exists(p_username) THEN
            RAISE_APPLICATION_ERROR(-20001, 'Username already exists');
        END IF;

        -- Check if email already exists
        IF email_exists(p_email) THEN
            RAISE_APPLICATION_ERROR(-20002, 'Email already exists');
        END IF;

        -- Generate UUID
        p_user_id := generate_uuid();

        -- Insert user (password is already hashed by application)
        INSERT INTO users (id, username, password, email, created_at, updated_at)
        VALUES (p_user_id, p_username, p_password, p_email, SYSTIMESTAMP, SYSTIMESTAMP);

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END create_user;

    FUNCTION get_user_by_id(p_user_id IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT id, username, email
            FROM users
            WHERE id = p_user_id;
        RETURN v_cursor;
    END get_user_by_id;

    FUNCTION get_user_by_username(p_username IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT id, username, email
            FROM users
            WHERE username = p_username;
        RETURN v_cursor;
    END get_user_by_username;

    FUNCTION get_user_by_email(p_email IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT id, username, email
            FROM users
            WHERE email = p_email;
        RETURN v_cursor;
    END get_user_by_email;

    PROCEDURE update_user(
        p_user_id IN VARCHAR2,
        p_username IN VARCHAR2 DEFAULT NULL,
        p_email IN VARCHAR2 DEFAULT NULL,
        p_password IN VARCHAR2 DEFAULT NULL
    ) IS
        v_count NUMBER;
    BEGIN
        -- Check if user exists
        SELECT COUNT(*) INTO v_count FROM users WHERE id = p_user_id;
        IF v_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'User not found');
        END IF;

        -- Update user
        UPDATE users
        SET username = NVL(p_username, username),
            email = NVL(p_email, email),
            password = NVL(p_password, password),
            updated_at = SYSTIMESTAMP
        WHERE id = p_user_id;

        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            IF p_username IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(-20001, 'Username already exists');
            ELSIF p_email IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(-20002, 'Email already exists');
            ELSE
                RAISE;
            END IF;
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END update_user;

    FUNCTION delete_user(p_user_id IN VARCHAR2) RETURN NUMBER IS
        v_count NUMBER;
        v_deleted NUMBER;
    BEGIN
        -- Check if user exists
        SELECT COUNT(*) INTO v_count FROM users WHERE id = p_user_id;
        IF v_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'User not found');
        END IF;

        -- Delete user
        DELETE FROM users WHERE id = p_user_id;
        v_deleted := SQL%ROWCOUNT;

        COMMIT;
        RETURN v_deleted;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END delete_user;

    FUNCTION username_exists(p_username IN VARCHAR2) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM users WHERE username = p_username;
        RETURN v_count > 0;
    END username_exists;

    FUNCTION email_exists(p_email IN VARCHAR2) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM users WHERE email = p_email;
        RETURN v_count > 0;
    END email_exists;

    PROCEDURE log_login_attempt(
        p_username IN VARCHAR2,
        p_success IN NUMBER,
        p_ip_address IN VARCHAR2 DEFAULT NULL,
        p_user_agent IN VARCHAR2 DEFAULT NULL,
        p_failure_reason IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO audit_login_attempts (id, username, success, ip_address, user_agent, failure_reason)
        VALUES (audit_seq.NEXTVAL, p_username, p_success, p_ip_address, p_user_agent, p_failure_reason);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Log error but don't fail the login process
            NULL;
    END log_login_attempt;

    PROCEDURE log_session_start(
        p_user_id IN VARCHAR2,
        p_token_hash IN VARCHAR2,
        p_ip_address IN VARCHAR2 DEFAULT NULL,
        p_user_agent IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO audit_sessions (id, user_id, token_hash, ip_address, user_agent)
        VALUES (audit_seq.NEXTVAL, p_user_id, p_token_hash, p_ip_address, p_user_agent);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Log error but don't fail the session
            NULL;
    END log_session_start;
END user_pkg;
/