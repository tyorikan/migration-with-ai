#!/usr/bin/env python3
"""
sfdc_csv_to_postgres.py

SFDC Data Loader / SFDX CLI でエクスポートした CSV ファイルを
PostgreSQL 用の CSV に変換するスクリプト。

使い方:
  python3 sfdc_csv_to_postgres.py <table_name> <input.csv> <output.csv>

例:
  python3 sfdc_csv_to_postgres.py accounts sfdc_export/Account.csv pg_import/accounts.csv
  python3 sfdc_csv_to_postgres.py daily_reports sfdc_export/DailyReport__c.csv pg_import/daily_reports.csv

対応テーブル:
  accounts, contacts, daily_reports, counseling_records
"""

import csv
import sys
from pathlib import Path

# ============================================================
# カラム名の変換ルール: SFDC → PostgreSQL
# ============================================================
COLUMN_MAPPINGS = {
    "accounts": {
        "Id": "id",
        "Name": "name",
        "StoreCode__c": "store_code",
        "Region__c": "region",
        "OpenDate__c": "open_date",
        "IsActive__c": "is_active",
        "Phone": "phone",
        "BillingCity": "billing_city",
        "BillingState": "billing_state",
        "LastVisitDate__c": "last_visit_date",
    },
    "contacts": {
        "Id": "id",
        "FirstName": "first_name",
        "LastName": "last_name",
        "Email": "email",
        "Phone": "phone",
        "Title": "title",
        "AccountId": "account_id",
    },
    "daily_reports": {
        "Id": "id",
        "Name": "name",
        "ReportDate__c": "report_date",
        "Supervisor__c": "supervisor_id",
        "Account__c": "account_id",
        "VisitStartTime__c": "visit_start_time",
        "VisitEndTime__c": "visit_end_time",
        "VisitPurpose__c": "visit_purpose",
        "OverallCondition__c": "overall_condition",
        "Summary__c": "summary",
        "NextAction__c": "next_action",
        "Status__c": "status",
        "ApprovedBy__c": "approved_by",
        "ApprovedDate__c": "approved_date",
    },
    "counseling_records": {
        "Id": "id",
        "Name": "name",
        "DailyReport__c": "daily_report_id",
        "Contact__c": "contact_id",
        "Category__c": "category",
        "Detail__c": "detail",
        "DurationMinutes__c": "duration_minutes",
        "FollowUpRequired__c": "follow_up_required",
        "FollowUpDate__c": "follow_up_date",
        "FollowUpNote__c": "follow_up_note",
    },
}

# Boolean に変換するカラム
BOOLEAN_COLUMNS = {"is_active", "follow_up_required"}

# Integer に変換するカラム
INTEGER_COLUMNS = {"duration_minutes"}


def convert_value(col_name: str, value: str) -> str:
    """SFDC の値を PostgreSQL 用に変換"""
    if value == "" or value is None:
        return ""

    # Boolean 変換
    if col_name in BOOLEAN_COLUMNS:
        return "true" if value.lower() in ("true", "1", "yes") else "false"

    # Integer 変換（SFDC は Number を小数で出力する場合がある: "30.0" → "30"）
    if col_name in INTEGER_COLUMNS:
        try:
            return str(int(float(value)))
        except ValueError:
            return value

    return value


def convert_csv(table_name: str, input_path: str, output_path: str):
    """SFDC CSV を PostgreSQL 用 CSV に変換"""
    mapping = COLUMN_MAPPINGS.get(table_name)
    if not mapping:
        print(f"❌ ERROR: Unknown table '{table_name}'")
        print(f"   Available tables: {', '.join(COLUMN_MAPPINGS.keys())}")
        sys.exit(1)

    input_file = Path(input_path)
    if not input_file.exists():
        print(f"❌ ERROR: Input file not found: {input_path}")
        sys.exit(1)

    # 出力ディレクトリを自動作成
    output_file = Path(output_path)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(input_path, "r", encoding="utf-8") as infile, \
         open(output_path, "w", encoding="utf-8", newline="") as outfile:

        reader = csv.DictReader(infile)

        # SFDC CSV のヘッダーから、マッピングに存在するカラムだけ抽出
        sfdc_columns = [col for col in reader.fieldnames if col in mapping]
        pg_columns = [mapping[col] for col in sfdc_columns]

        if not pg_columns:
            print(f"❌ ERROR: No matching columns found in CSV headers")
            print(f"   CSV headers: {reader.fieldnames}")
            print(f"   Expected: {list(mapping.keys())}")
            sys.exit(1)

        writer = csv.DictWriter(outfile, fieldnames=pg_columns)
        writer.writeheader()

        count = 0
        skipped = 0
        for row in reader:
            pg_row = {}
            for sfdc_col in sfdc_columns:
                pg_col = mapping[sfdc_col]
                pg_row[pg_col] = convert_value(pg_col, row.get(sfdc_col, ""))
            writer.writerow(pg_row)
            count += 1

        print(f"✅ {table_name}: {count} records converted")
        print(f"   Input:  {input_path}")
        print(f"   Output: {output_path}")
        print(f"   Columns: {', '.join(pg_columns)}")


def main():
    if len(sys.argv) == 1:
        # 引数なし → 全テーブルのバッチ変換
        print("=" * 60)
        print("SFDC CSV → PostgreSQL CSV 変換ツール")
        print("=" * 60)
        print()
        print("使い方:")
        print("  python3 sfdc_csv_to_postgres.py <table> <input.csv> <output.csv>")
        print()
        print("バッチ変換例:")
        print("  mkdir -p sfdc_export pg_import")
        print()
        for table, mapping in COLUMN_MAPPINGS.items():
            sfdc_obj = {
                "accounts": "Account",
                "contacts": "Contact",
                "daily_reports": "DailyReport__c",
                "counseling_records": "CounselingRecord__c",
            }[table]
            print(f"  python3 sfdc_csv_to_postgres.py {table} "
                  f"sfdc_export/{sfdc_obj}.csv pg_import/{table}.csv")
        print()
        sys.exit(0)

    if len(sys.argv) != 4:
        print("Usage: python3 sfdc_csv_to_postgres.py <table_name> <input.csv> <output.csv>")
        sys.exit(1)

    convert_csv(sys.argv[1], sys.argv[2], sys.argv[3])


if __name__ == "__main__":
    main()
