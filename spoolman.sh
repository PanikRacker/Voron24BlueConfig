#!/bin/bash

spoolman_folder=~/printer_data/config/Spoolman/data
branch=master

grab_version(){
  if [ ! -z "$spoolman_folder" ]; then
    cd "$spoolman_folder"
    spoolman_commit=$(git rev-parse --short=7 HEAD)
    m1="Spoolman on commit: $spoolman_commit"
    cd ..
  fi
}

push_config(){
  cd $spoolman_folder
  git pull origin $branch --no-rebase
  git add .
  current_date=$(date +"%Y-%m-%d %T")
  git commit -m "Autocommit from $current_date" -m "$m1"
  git push origin $branch
}

grab_version
push_config
