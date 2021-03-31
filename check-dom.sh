#!/usr/bin/env bash

server_name_list_file="$1"

file_data=$(cat ${server_name_list_file})

old_stat=$(stat ${server_name_list_file})

function checkdom() {
	check_arr=()
	domstr=$1
	readarray -d "." -t domarr <<< $domstr
	check_arr+=${domstr}

	arr_size="${#domarr[@]}"
	i=0
	while [ "${i}" -ne "${arr_size}" ]
	do
		arr_max=$((arr_size-1))
		dom_str=""
		for l in $(seq ${i} ${arr_max}); do 
			dom_str+=".${domarr[$l]}"
		done
		check_arr+=(${dom_str})
		i=$((i+1))
	done
	check_str=""
	for s in "${check_arr[@]}"; do
		s=$(echo ${s}|sed -e "s@\.@\\\.@g" -e "s@\-@\\\-@g")
		if [ -z "${check_str}" ];then
			check_str+="${s}"
		else
                        check_str+="|${s}"
		fi
	done
	echo "^(${check_str})$"
}

while IFS= read -r line; do
	check_str=$(checkdom "$line")
	echo "${file_data}" |egrep "${check_str}" >/dev/null
	RES=$?
	if [ "${RES}" -gt "0" ];then
  		echo "ERR"
	else
		echo "OK"
	fi
	current_stat=$(stat ${server_name_list_file})
	diff <( echo "${old_stat}" ) <( echo "${current_stat}" )
	if [ ! -z "${DIFF}"];then
		file_data=$(cat ${server_name_list_file})
	fi
done

