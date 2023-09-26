#!/bin/bash

# ========== << Declare essential variables >> ==========
SOFTWARE_COMPONENT="NONE"
WORKDIR="NONE"
SETUP_SCRIPT="NONE"
CODEBASE_NAME="NONE"
BUILD_NAME="NONE"
OUTPUT_DIR="NONE"
ENV_TXT="NONE"
BBPATH_TXT="NONE"
BBAPPEND_TXT="NONE"
BBSUM_TXT="NONE"
RECIPES_DISTRO_CSV="NONE"


# ========== << Generate log >> ==========
function generate_log(){

	echo "Date: $(date)"
	echo ""

	echo "============================="
	echo "CMD"
	echo "$(basename ${0}) <sw component name> <build dir path> <setup script path>" 
	echo "============================="

	echo ""
	echo "<sw component name>: ${SOFTWARE_COMPONENT}"
	echo "<build dir path>:    ${WORKDIR}"
	echo "<setup script path>: ${SETUP_SCRIPT}"
	echo ""

	echo "============================="
	echo "OUTPUT FILES"
	echo "============================="

	echo ""
	printf "%s\n" "${ENV_TXT}"
	printf "%s\n" "${BBSUM_TXT}"
	printf "%s\n" "${BBPATH_TXT}"
	printf "%s\n" "${BBAPPEND_TXT}"
	printf "%s\n" "${RECIPES_DISTRO_CSV}"
}


# ========== << HELP MESSAGE >> ==========

function HELP(){
	echo "usage: $(basename ${0}) <sw component name> <build dir path> <setup script path>" 
	echo ""

	printf "%-20s : %-40s %-30s\n" "<sw component name>" "NAME of software component"        "(e.g. ccsp-wifi-agent)"
	printf "%-20s : %-40s %-30s\n" "<rdk build dir>"     "PATH of build directory"           "(e.g. \${RDKB_CODEBASE}/build-mt6890)"
	printf "%-20s : %-40s %-30s\n" "<setup script path>" "PATH of setup-environment script"  "(e.g. \${RDKB_CODEBASE}/meta-rdk/setup-environment)"
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

	# output the recipes location for the specific package to "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbpath.txt"
	bitbake-layers show-recipes -f ${SOFTWARE_COMPONENT} > "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbpath.txt"

	# parse "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbpath.txt" to get the bb file
	cat "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbpath.txt" | awk \
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

	bitbake-layers show-appends > "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbappendpath.txt"
	cat "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbappendpath.txt" | awk \
	--assign package_name=${SOFTWARE_COMPONENT} \
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

function get_layer_path(){

	local recipe_path=$1
	
	echo ${recipe_path} | awk -F"/" \
	'
	BEGIN{
		layer_path="";
	}
	{
		for(i=1; i<=NF; i++){
			if( length($i) != 0 ){
				layer_path = layer_path"/"$i
			}
			if( match($i, /meta-.*/) ){
				break;
			}
		}
	}
	END{
		print layer_path
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
	local package_name

	count=1
	for path in ${paths}
	do
		layer_name=$(get_layer_name $path)
		layer_path=$(get_layer_path $path)
		package_name=${path##*/}

        printf "==========================================================\n"
        printf "Layer  : %s \n" "${layer_name}"
        printf "Recipe : %s \n" "${package_name}"
		printf "Path   : %s \n" "${path}"
        printf "==========================================================\n\n"

		cat ${path}

		# search the pattern "require aaa/bbb/ccc.inc" and then extract "ccc.inc"
		for inc_file_name in $(cat ${path} | grep "require" | awk -F"[/ ]" '{print $NF}')
		do
			inc_file_path="$(find ${layer_path} -name ${inc_file_name})"
			echo ""                                 >> "${OUTPUT_DIR}/${layer_name}_${inc_file_name}"
			echo "#### path: ${inc_file_path} ####" >> "${OUTPUT_DIR}/${layer_name}_${inc_file_name}"
			echo ""                                 >> "${OUTPUT_DIR}/${layer_name}_${inc_file_name}"
			cat ${inc_file_path}                    >> "${OUTPUT_DIR}/${layer_name}_${inc_file_name}"
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

# define essential variables
SOFTWARE_COMPONENT=${1}
WORKDIR=${2}
SETUP_SCRIPT=${3}

CODEBASE_NAME=$(get_codebase_name ${WORKDIR})
BUILD_NAME=$(get_build_name ${WORKDIR})
OUTPUT_DIR="$(pwd)/recipe_tracking/${CODEBASE_NAME}_${BUILD_NAME}_${SOFTWARE_COMPONENT}"

BBPATH_TXT="${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbpath.txt"
BBAPPEND_TXT="${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbappendpath.txt"
ENV_TXT="${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_environment.txt"
RECIPES_DISTRO_CSV="${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_recipes_distribution.csv"
BBSUM_TXT="${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbsum.txt"


# create folder
if [[ -d ${OUTPUT_DIR} ]]; then
	read -p "overwrite ${OUTPUT_DIR}? (y/n)"
	if [[ ${REPLY} == "y" ]]; then
		echo "rm ${OUTPUT_DIR} -rf"
		rm ${OUTPUT_DIR} -rf
	fi
fi
echo "mkdir -p ${OUTPUT_DIR}"
mkdir -p ${OUTPUT_DIR}

# move to work dir
cd $(dirname ${WORKDIR})

# setup oe environment
source ${SETUP_SCRIPT} ${BUILD_NAME}

# get bb file and bbapend files
bb_path=$(get_bb_path)
bbappend_path=$(get_bbappend_paths)

# collect all paths of bb/bbappend files into "paths"
paths="${bb_path[@]} ${bbappend_path[@]}"

# get environment dump and output into the file "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_environment.txt"
bitbake -e ${SOFTWARE_COMPONENT} > "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_environment.txt"

# Generate recipe list with csv format
{
	generate_recipe_list ${paths}
} > "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_recipes_distribution.csv"

# Generate sumary content of bb and bbapend files
{
	generate_finalized_recipe ${paths}
} > "${OUTPUT_DIR}/${SOFTWARE_COMPONENT}_bbsum.txt"

# generate log
generate_log > ${OUTPUT_DIR}/log.txt
