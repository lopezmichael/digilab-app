#!/usr/bin/env python3
"""
Migration: Add classification review fields to deck_requests table.

Adds columns for the auto-classification workflow:
- suggested_archetype_name: What classification thought it was
- decklist_json: The actual card list for admin review
- source: Where the request came from ('manual', 'limitless_sync', 'classification')
- result_id: Link back to result for updating after approval

Usage:
    python scripts/migrate_deck_requests_classification.py           # Run migration
    python scripts/migrate_deck_requests_classification.py --dry-run # Preview only
"""

import os
import argparse
import psycopg2
from dotenv import load_dotenv

load_dotenv()

def get_neon_connection():
    """Connect to Neon PostgreSQL."""
    return psycopg2.connect(
        host=os.getenv("NEON_HOST"),
        database=os.getenv("NEON_DATABASE", "neondb"),
        user=os.getenv("NEON_USER"),
        password=os.getenv("NEON_PASSWORD"),
        sslmode="require"
    )

def column_exists(cursor, table, column):
    """Check if a column exists in a table."""
    cursor.execute("""
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = %s AND column_name = %s
        )
    """, (table, column))
    return cursor.fetchone()[0]

def main():
    parser = argparse.ArgumentParser(description='Add classification fields to deck_requests')
    parser.add_argument('--dry-run', action='store_true', help='Preview changes without applying')
    args = parser.parse_args()

    print("=" * 60)
    print("Migration: Add classification review fields to deck_requests")
    print("=" * 60)

    conn = get_neon_connection()
    cursor = conn.cursor()

    # Define new columns to add
    new_columns = [
        ("suggested_archetype_name", "VARCHAR", None),
        ("decklist_json", "TEXT", None),
        ("source", "VARCHAR", "'manual'"),
        ("result_id", "INTEGER", None),
    ]

    changes = []
    for col_name, col_type, default in new_columns:
        if column_exists(cursor, "deck_requests", col_name):
            print(f"  Column '{col_name}' already exists, skipping")
        else:
            default_clause = f" DEFAULT {default}" if default else ""
            sql = f"ALTER TABLE deck_requests ADD COLUMN {col_name} {col_type}{default_clause}"
            changes.append((col_name, sql))
            print(f"  Will add column: {col_name} {col_type}{default_clause}")

    if not changes:
        print("\nNo changes needed - all columns already exist.")
        cursor.close()
        conn.close()
        return

    if args.dry_run:
        print("\n[DRY RUN] Would execute:")
        for col_name, sql in changes:
            print(f"  {sql};")
    else:
        print(f"\nApplying {len(changes)} changes...")
        for col_name, sql in changes:
            cursor.execute(sql)
            print(f"  Added column: {col_name}")
        conn.commit()
        print("Migration complete!")

    cursor.close()
    conn.close()

if __name__ == "__main__":
    main()
