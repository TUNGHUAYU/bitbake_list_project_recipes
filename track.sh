#!/bin/bash

# ========== << PATHs of OUTPUT FILES >> ==========
# "$(pwd)/recipe_tracking/${codebase_name}_${build_name}_${package_name}"	: output folder.
# "${output_dir}/${package_name}_bbpath.txt"								: record the bb files of package name.
# "${output_dir}/${package_name}_bbappendpath.txt"							: record the bbapend files of package name.
# "${output_dir}/${package_name}_environment.txt"							: record the environment variables of package name.
# "${output_dir}/${package_name}_recipes_distribution.csv"					: list bb and bbappend paths with csv format.
# "${output_dir}/${package_name}_bbsum.txt"									: record all content of bb and bbapend files.
function DUMP_OUTPUT_FILES(){
	echo "output files:"
	printf "%s\n" "${output_dir}/${package_name}_bbpath.txt"
	printf "%s\n" "${output_dir}/${package_name}_bbappendpath.txt"
	printf "%s\n" "${output_dir}/${package_name}_environment.txt"
	printf "%s\n" "${output_dir}/${package_name}_recipes_distribution.csv"
	printf "%s\n" "${output_dir}/${package_name}_bbsum.txt"
}


# ========== << HELP MESSAGE >> ==========

function HELP(){
	echo "usage: $(basename ${0}) <package name> <rdk build dir> <setup script path>" 
	echo ""

	printf "%-20s : %-30s %-30s\n" "<package name>" "package name" "(e.g. ccsp-wifi-agent)"
	printf "%-20s : %-30s %-30s\n" "<rdk build dir>" "build directory path" "(e.g. \${workplace}/build-mt6890)"
	printf "%-20s : %-30s %-30s\n" "<setup script path>" "setup-environment shell script" "(e.g. \${workplace}/meta-rdk/setup-environment)"
}

# ========== << functions >> ==========

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

	# output the recipes location for the specific package to "${output_dir}/${package_name}_bbpath.txt"
	bitbake-layers show-recipes -f ${package_name} > "${output_dir}/${package_name}_bbpath.txt"

	# parse "${output_dir}/${package_name}_bbpath.txt" to get the bb file
	cat "${output_dir}/${package_name}_bbpath.txt" | awk \
	'
	{
		if ( match($0, /Matching recipes:/) ){
			flag_match=1
			NR_match=NR
		}

		n = NR - NR_match

		# ONLY the first path under the "Matching recipes:" line is legal bb file.
		if ( flag_match && n == 1 ){
			bb_path = $0
		}

		# Other paths under the "Matching recipes:" line is illegal bb files. ( multiple bb file case )
		if ( flag_match && n > 1 ){
			_n = n -1
			bb_multiple_path_arr[_n] = $0
		}
	}

	END{
		if ( flag_match ){
			print bb_path
		}
	}
	'
}

function get_bbappend_paths(){

	bitbake-layers show-appends > "${output_dir}/${package_name}_bbappendpath.txt"
	cat "${output_dir}/${package_name}_bbappendpath.txt" | awk \
	--assign package_name=${package_name} \
	'
	BEGIN{
		regex = ".*.bb:"
		# printf("%s -> %s\n", "regex", regex)
		flag_match = 0
	}

	{
		if ( match($0, regex) ){
			split($0, arr, ".")
			_package_name = arr[1]
			if ( _package_name ~ "^"package_name ){
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
	local package_name
	
	printf "%s,%s,%s,%s\n" "No." "Layer Name" "Recipe Name" "Full Path"

	count=1
	for path in ${paths}
	do
		layer_name=$(get_layer_name $path)
		package_name=${path##*/}
		printf "%s,%s,%s,%s\n" "${count}" "${layer_name}" "${package_name}" "${path}"
		let "count+=1"
	done
}

function generate_finalized_recipe(){

	local paths="$@"

	count=1
	for path in ${paths}
	do
		layer_name=$(get_layer_name $path)
		package_name=${path##*/}

        printf "==========================================================\n"
        printf "Layer  : %s \n" "${layer_name}"
        printf "Recipe : %s \n" "${package_name}"
		printf "Path   : %s \n" "${path}"
        printf "==========================================================\n\n"

		cat ${path}

		for inc_file_name in $(cat ${path} | grep "require" | awk -F"[/ ]" '{print $NF}')
		do
			inc_file_path="$(dirname ${path})/${inc_file_name}"
			echo "" >> ${output_dir}/${inc_file_name}
			echo "#### path: ${inc_file_path} ####" >> ${output_dir}/${inc_file_name}
			echo "" >> ${output_dir}/${inc_file_name}
			cat ${inc_file_path} >> ${output_dir}/${inc_file_name}
		done

		printf "\n"

	done
}

# ========== << main >> ==========

# argument check
if [[ $# != 3 ]];then 
	HELP
	exit 1
fi

# assign value
package_name=${1}
work_dir=${2}
setup_environment_path=${3}
codebase_name=$(get_codebase_name ${work_dir})
build_name=$(get_build_name ${work_dir})
output_dir="$(pwd)/recipe_tracking/${codebase_name}_${build_name}_${package_name}"

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

# get bb file and bbapend files
bb_path=$(get_bb_path)
bbappend_path=$(get_bbappend_paths)

# get environment dump and output into the file "${output_dir}/${package_name}_environment.txt"
bitbake -e ${package_name} > "${output_dir}/${package_name}_environment.txt"

# Generate paths with bb file and bbapend files
paths="${bb_path[@]} ${bbappend_path[@]}"
echo "paths:"
printf "%s\n" ${paths[@]}

# Generate recipe list with csv format
{
	generate_recipe_list ${paths}
} > "${output_dir}/${package_name}_recipes_distribution.csv"

# Generate sumary content of bb and bbapend files
{
	generate_finalized_recipe ${paths}
} > "${output_dir}/${package_name}_bbsum.txt"

# list all paths of output files
DUMP_OUTPUT_FILES
