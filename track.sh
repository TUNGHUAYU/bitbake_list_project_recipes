#!/bin/bash

function HELP(){
	echo "usage: $(basename ${0}) <recipe name> <rdk build dir> <setup script path>" 
	echo ""

	printf "%-20s : %-30s %-30s\n" "<recipe name>" "recipe name" "(e.g. ccsp-wifi-agent)"
	printf "%-20s : %-30s %-30s\n" "<rdk build dir>" "build directory path" "(e.g. \${codebase}/build-mt6890)"
	printf "%-20s : %-30s %-30s\n" "<setup script path>" "setup-environment shell script" "(e.g. \${codebase}/meta-rdk/setup-environment)"
}

# << functions >>

function get_build_name(){
	local path=$1
	
	echo "${path}" | awk -F"/" \
	'
	{ 
		print $(NF)
	}
	'
}

function get_codebase_name(){
	local path=$1
	
	echo "${path}" | awk -F"/" \
	'
	{ 
		print $(NF-1)
	}
	'
}

function get_bb_path(){


	bitbake-layers show-recipes -f ${recipe_name} > "${output_dir}/${recipe_name}_bbpath.txt"
	cat "${output_dir}/${recipe_name}_bbpath.txt" | awk \
	'
	{

		if ( match($0, /Matching recipes:/) ){
			flag_match=1
			NR_match=NR
		}

		n = NR - NR_match
		if ( flag_match && n > 0 ){
			bb_path_arr[n] = $0
		}
	}

	END{
		for ( i=1; i<=length(bb_path_arr); i++ ){
			print bb_path_arr[i]
		}
	}
	'
}

function get_bbappend_paths(){

	bitbake-layers show-appends > "${output_dir}/${recipe_name}_bbappendpath.txt"
	cat "${output_dir}/${recipe_name}_bbappendpath.txt" | awk \
	--assign recipe_name=${recipe_name} \
	'
	BEGIN{
		regex = ".*.bb:"
		# printf("%s -> %s\n", "regex", regex)
		flag_match = 0
	}

	{
		if ( match($0, regex) ){
			split($0, arr, ".")
			_recipe_name = arr[1]
			if ( _recipe_name == recipe_name ){
				flag_match = 1
				NR_match = NR
			} else {
				flag_match = 0
			}
		}

		n = NR - NR_match 
		if ( flag_match && n > 0 ){
			bbappend_path_arr[n] = $1
		}
	}

	END{
		for ( i=1; i<=length(bbappend_path_arr); i++ ){
			print bbappend_path_arr[i]
		}
	}
	'
}

function get_layer_name(){

	local recipe_path=$1
	
	echo "${recipe_path}" | awk -F"/" \
	'
	{
		for(i=1; i<=NF; i++){
			if ( match($i, /meta-.*/) ){
				layer_name = $i
			}
		}
	}
	END{
		print layer_name
	}
	'
}

function generate_recipe_list(){

	local paths="$@"
	
	printf "%s,%s,%s,%s\n" "No." "Layer Name" "Recipe Name" "Full Path"

	count=1
	for path in ${paths}
	do
		layer_name=$(get_layer_name $path)
		recipe_name=${path##*/}
		printf "%s,%s,%s,%s\n" "${count}" "${layer_name}" "${recipe_name}" "${path}"
		let "count+=1"
	done
}

function generate_finalized_recipe(){

	local paths="$@"

	count=1
	for path in ${paths}
	do
		layer_name=$(get_layer_name $path)
		recipe_name=${path##*/}
		
		printf "====== %s / %s ======\n" "${layer_name}" "${recipe_name}"
		printf "====== %s ===== \n" "${path}"
		printf "\n"

		cat ${path}

		printf "\n"

	done
}

# << main >>

# argument check
if [[ $# != 3 ]];then 
	HELP
	exit 1
fi

# assign value
recipe_name=${1}
work_dir=${2}
setup_environment_path=${3}
ori_dir=$(pwd)
codebase_name=$(get_codebase_name ${work_dir})
build_name=$(get_build_name ${work_dir})
output_dir="$(pwd)/recipe_tracking/${codebase_name}_${build_name}_${recipe_name}"

# create folder
if [[ -d ${output_dir} ]]; then
	read -p "overwrite ${output_dir}? (y/n)"
	if [[ ${REPLY} == "y" ]]; then
		echo "rm ${output_dir} -rf"
		rm ${output_dir} -rf
	fi
fi

echo "mkdir -p ${output_dir}"
mkdir -p ${output_dir}


# move to work dir
cd $(dirname ${work_dir})

# setup oe environment
source ${setup_environment_path} ${build_name}

# 
bb_path=$(get_bb_path)
bbappend_path=$(get_bbappend_paths)

# 
paths="${bb_path[@]} ${bbappend_path[@]}"

echo "paths: ${paths[@]}"

{
generate_recipe_list ${paths}
} > "${output_dir}/${recipe_name}_recipe_list.csv"

{
	generate_finalized_recipe ${paths}
} > "${output_dir}/${recipe_name}_finalized.txt"
