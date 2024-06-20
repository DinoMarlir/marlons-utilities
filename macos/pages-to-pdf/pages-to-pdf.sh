#!/bin/bash

# Adjust paths
read -p "Enter the path to the input folder (e.g., /Users/marlonroder/Downloads/Steckbriefe): " input_folder
read -p "Enter the path to the output folder (e.g., /Users/marlonroder/Downloads/Steckbriefe/output): " output_folder

# Iterate through all Pages files in the input folder
for pages_file in "$input_folder"/*.pages; do
    # Extract base name without extension
    base_name=$(basename "$pages_file" .pages)

    # Convert Pages file to PDF
    /usr/bin/env osascript -e "tell application \"Pages\" to open POSIX file \"$pages_file\"" -e "tell application \"Page$
done

echo "All Pages files have been successfully converted to PDF!"

# Wait for user input before exiting the script
read -p "Press Enter to continue..."
