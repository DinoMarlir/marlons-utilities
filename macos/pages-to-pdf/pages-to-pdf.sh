#!/bin/bash

# Adjust paths
input_folder="/Users/myuser/documents/"  # Current folder
output_folder="/Users/myuser/output/output"  # Folder for PDF files

# Iterate through all Pages files in the input folder
for pages_file in "$input_folder"/*.pages; do
    # Extract base name without extension
    base_name=$(basename "$pages_file" .pages)

    # Convert Pages file to PDF
    /usr/bin/env osascript -e "tell application \"Pages\" to open POSIX file \"$pages_file\"" -e "tell application \"Page$
done

echo "All Pages files have been successfully converted to PDF!"