#!/usr/bin/env bash

function doforall_asyncandwait(){
    local cmd=$1
    shift
    local list=("$@")
    tput setaf 3; tput bold; 
    echo "${cmd}" "${list[@]}"
    tput sgr0
    pids=()
    for i in "${list[@]}"; do
        ${cmd} "${i}" &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

function doforall_asyncandwait_witharg(){
    local cmd=$1
    local arg=$2
    shift
    shift
    local list=("$@")
    tput setaf 3; tput bold; 
    echo "${cmd}" "${arg}" "${list[@]}"
    tput sgr0
    pids=()
    for i in "${list[@]}"; do
        ${cmd} "${i}" "${arg}" &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

function doforall_asyncandwait_withindex(){
    local cmd=$1
    shift
    local list=("$@")
    tput setaf 3; tput bold; 
    echo "${cmd}" "${list[@]}" "(with index)"
    tput sgr0
    pids=()
    index=1
    for i in "${list[@]}"; do
        ${cmd} "${i}" "${index}" &
        pids+=($!)
        index=$((index+1))
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

function doforall(){
    local cmd=$1
    shift
    local list=("$@")
    tput setaf 3; tput bold; 
    echo "${cmd}" "${list[@]}"
    tput sgr0
    for i in "${list[@]}"; do
        ${cmd} "${i}"
    done
}