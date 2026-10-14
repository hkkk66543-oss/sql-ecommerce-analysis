"""Prepare Kaggle CSV dates for the project's legacy STR_TO_DATE expressions.

Usage: python scripts/prepare_olist_csv.py RAW_DIRECTORY NEW_OUTPUT_DIRECTORY
Original files are never edited. ISO seconds are truncated to minute precision
to match the historical scripts; unknown date formats fail with row context.
"""
import csv
import sys
from datetime import datetime
from pathlib import Path

DATE_FIELDS = {
    'order_purchase_timestamp', 'order_approved_at',
    'order_delivered_carrier_date', 'order_delivered_customer_date',
    'order_estimated_delivery_date', 'shipping_limit_date',
    'review_creation_date', 'review_answer_timestamp',
}


def convert_date(value):
    if not value.strip():
        return ''
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d',
                '%m/%d/%Y %H:%M', '%m/%d/%Y %H:%M:%S'):
        try:
            parsed = datetime.strptime(value.strip(), fmt)
            return f'{parsed.month}/{parsed.day}/{parsed.year} {parsed:%H:%M}'
        except ValueError:
            pass
    raise ValueError(f'Unsupported date: {value!r}')


def main():
    source, target = map(Path, sys.argv[1:])
    files = sorted(source.glob('*.csv'))
    if not files:
        raise ValueError('No CSV files in input directory')
    target.mkdir(parents=True, exist_ok=False)
    for path in files:
        with path.open(encoding='utf-8-sig', newline='') as src, \
                (target / path.name).open('x', encoding='utf-8', newline='') as dst:
            reader = csv.DictReader(src)
            writer = csv.DictWriter(dst, fieldnames=reader.fieldnames)
            writer.writeheader()
            for line, row in enumerate(reader, 2):
                for field in DATE_FIELDS.intersection(row):
                    try:
                        row[field] = convert_date(row[field])
                    except ValueError as exc:
                        raise ValueError(f'{path.name}:{line}:{field}: {exc}') from exc
                writer.writerow(row)
        print(path.name)


if __name__ == '__main__':
    main()
