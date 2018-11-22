#!/usr/bin/bash

# error codes
E_NOTABASH=1
E_OLD_BASH=2
E_FEW_ARGS=3
E_INV_CONF=4
E_INV_TASK=5
E_NO_SLURM=6
E_RUN_FAIL=7


# coloring support
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_BLUE='\033[1;34m'
C_YELLOW='\033[1;33m'
C_PURPLE='\033[1;35m'
C_NC='\033[0m'


# print header
echo -e "${C_BLUE}+-----------------------------------------------+${C_NC}"
echo -e "${C_BLUE}|                                               |${C_NC}"
echo -e "${C_BLUE}| ${C_YELLOW}Lomonosov-2 batch wrapper v0.1.0 (22.11.2018) ${C_BLUE}|${C_NC}"
echo -e "${C_BLUE}|           ${C_YELLOW}Written by Viktor Drobot            ${C_BLUE}|${C_NC}"
echo -e "${C_BLUE}|                                               |${C_NC}"
echo -e "${C_BLUE}+-----------------------------------------------+${C_NC}"
echo
echo


# some checks
if [ -z "$BASH_VERSION" ]
then
    echo -e "${C_RED}ERROR: this script support only BASH interpreter! Exiting.${C_NC}" >&2
    exit $E_NOTABASH
fi

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]
then
    echo -e "${C_RED}ERROR: this script needs BASH 4.0 or greater! Your current version is $BASH_VERSION. Exiting.${C_NC}" >&2
    exit $E_OLD_BASH
fi

if ! command -v sbatch > /dev/null 2>&1
then
    echo -e "${C_RED}ERROR: no SLURM tools are found (maybe you forgot about 'module load'?)! Exiting.${C_NC}" >&2
    exit $E_NO_SLURM;
fi

if [[ "$#" -ne 1 ]]
then
    echo "Usage: $0 taskfile"
    exit $E_FEW_ARGS
fi


# list of known keywords
KEYWORDS="DATAROOT AMBERROOT RUNTIME PARTITION NUMNODES BIN TASK"


# some defaults
SLEEPTIME=5
AMBERTASK="${HOME}/_scratch/opt/l2-multimd/amber-wrapper.sh"


# default settings for executing tasks
DATAROOT=''
AMBERROOT=''
RUNTIME='1-00:00:00'
PARTITION='compute'

declare -i NUMNODES
NUMNODES=3

BIN="pmemd.cuda.MPI"

declare -i NUMTASKS
NUMTASKS=0


# here we will store our configurations
declare -a T_DIRS
declare -a T_NODES
declare -a T_BINS
declare -a T_PRMTOPS
declare -a T_CONFIGS
declare -a T_COORDS
declare -a T_OUTPUTS
declare -a T_RESTARTS
declare -a T_TRAJS
declare -a T_INFOS


# remove preceding spaces from the string
chomp () {
    echo "$1" | sed -e 's/^[ \t]*//'
}


# parse TASK keyword
task () {
    declare -i idx
    idx="$1"

    shift

    # ugly hack - rebuild positional parameters list from passed argument string
    declare -a p
    eval p=($@)
    set -- "${p[@]}"

    T_DIRS[$idx]="$1" # store directory name for current task
    shift

    # apply default parameters from config file
    T_NODES[$idx]="$NUMNODES"
    T_BINS[$idx]="$BIN"
    T_PRMTOPS[$idx]="${T_DIRS[$idx]}.prmtop"
    T_CONFIGS[$idx]="${T_DIRS[$idx]}.in"
    T_COORDS[$idx]="${T_DIRS[$idx]}.rst"
    T_OUTPUTS[$idx]="${T_DIRS[$idx]}.out"
    T_RESTARTS[$idx]="${T_DIRS[$idx]}.rst"
    T_TRAJS[$idx]="${T_DIRS[$idx]}.nc"
    T_INFOS[$idx]="${T_DIRS[$idx]}.mdinfo"

    # parse remaining positional parameters
    while [[ $# -gt 0 ]]
    do
        local token="$1"

        case "$token" in
            -N|--nodes)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_NODES[$idx]="$2"
                shift 2
                ;;

            -b|--bin)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_BINS[$idx]="$2"
                shift 2
                ;;

            -p|--prmtop)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_PRMTOPS[$idx]="$2"
                shift 2
                ;;

            -i|--config)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_CONFIGS[$idx]="$2"
                shift 2
                ;;

            -c|--coord)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_COORDS[$idx]="$2"
                shift 2
                ;;

            -o|--out)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_OUTPUTS[$idx]="$2"
                shift 2
                ;;

            -r|--restart)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_RESTARTS[$idx]="$2"
                shift 2
                ;;

            -x|--traj)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_TRAJS[$idx]="$2"
                shift 2
                ;;

            -inf|--mdinfo)
                if [[ "$#" -lt 2 ]]
                then
                    echo -e "${C_RED}ERROR: something wrong with the task definition #$((idx + 1)) (line #$lineno)!${C_NC}" >&2
                    exit $E_INV_TASK
                fi

                T_INFOS[$idx]="$2"
                shift 2
                ;;

            *)
                echo -e "${C_RED}WARNING: skipping unknown parameter [$token] in task definition #$((idx + 1)) (line #$lineno)...${C_NC}" >&2
                shift
                ;;
        esac
    done
}


# main script starts here


# some helpful variables
declare -i lineno
lineno=0

declare -i task_idx
task_idx=0


# process given taskfile
while IFS='' read -r line || [[ -n "$line" ]]; do
    # prepare line for parsing
    let lineno++
    line=$(chomp "$line")

    # ignore comments and empty lines
    if [[ "$line" == \#* || -z "$line" ]]
    then
        continue
    fi

    # get keyword from line
    KEYWORD=`echo "$line" | awk '{print $1}'`

    # check if our keyword is supported
    if ! echo "$KEYWORDS" | grep -i -q -P "(^|[[:space:]])$KEYWORD(\$|[[:space:]])"
    then
        echo -e "${C_RED}WARNING: ignoring unknown keyword [$KEYWORD] (line #$lineno)...${C_NC}" >&2
        continue
    fi

    # extract remaining parameters and store needed data
    PARAMS=$(chomp "`echo "$line" | awk '{$1 = ""; print $0}'`")

    case "${KEYWORD^^}" in # TODO parse keywords with one spaces-free parameter in robust way (such as awk '{print $1}')
        "DATAROOT")
            DATAROOT="$PARAMS"
            ;;

        "AMBERROOT")
            AMBERROOT="$PARAMS"
            ;;

        "RUNTIME") # TODO see above
            RUNTIME="$PARAMS"
            ;;

        "PARTITION") # TODO see above
            PARTITION="$PARAMS"
            ;;

        "NUMNODES") # TODO see above
            NUMNODES="$PARAMS"
            ;;

        "BIN")
            BIN="$PARAMS"
            ;;

        "TASK")
            task $task_idx "$PARAMS"

            let task_idx++
            ;;

        *)
            echo "$KEYWORD -- $PARAMS"
            ;;
    esac
done < "$1"


# total number of task to run
declare -i NUMTASKS
NUMTASKS="$task_idx"


# check if something wrong with given taskfile, e. g. necessary keywords are omitted or no tasks to run
if [[ -z "$DATAROOT" || -z "$AMBERROOT" || -z "$RUNTIME" || -z "$PARTITION" || "$NUMTASKS" -eq 0 ]]
then
    echo -e "${C_RED}ERROR: something wrong with taskfile (check DATAROOT, AMBERROOT, RUNTIME, PARTITION directives and the number of tasks given)!${C_NC}" >&2
    exit $E_INV_CONF
fi


# print short summary about requested job and prepare command lines
echo -e "${C_BLUE}===========${C_NC}"
echo -e "${C_BLUE}JOB SUMMARY${C_NC}"
echo -e "${C_BLUE}===========${C_NC}"
echo -e "Base data directory is ${C_YELLOW}[$DATAROOT]${C_NC}"
echo -e "AMBER is installed into ${C_YELLOW}[$AMBERROOT]${C_NC}"
echo -e "Time limit for the whole job is ${C_YELLOW}[$RUNTIME]${C_NC}"
echo -e "We will use ${C_YELLOW}[$PARTITION]${C_NC} partition to run our tasks"
echo -e "One task will consume ${C_YELLOW}[$NUMNODES]${C_NC} nodes by default"
echo -e "Default executable is ${C_YELLOW}[$BIN]${C_NC}"
echo -e "Will run ${C_YELLOW}[$NUMTASKS]${C_NC} tasks"
echo
echo

echo -e "${C_BLUE}===========================${C_NC}"
echo -e "${C_BLUE}TASKS CONFIGURATION DETAILS${C_NC}"
echo -e "${C_BLUE}===========================${C_NC}"

# error counter
declare -i NUMERRORS
NUMERRORS=0

# total number of nodes to be requested
declare -i TOTALNODES
TOTALNODES=0

# file with final list of directories to be processed
RUNLIST="$DATAROOT/runlist.$$"
:> "$RUNLIST"

for ((task_idx=0; task_idx < NUMTASKS; task_idx++))
do
    let "TOTALNODES += ${T_NODES[$task_idx]}"

    echo -e "${C_PURPLE}>> Task #$((task_idx + 1)) <<${C_NC}"
    echo -e "Data directory is ${C_YELLOW}[${T_DIRS[$task_idx]}]${C_NC}"
    echo -e "Will use ${C_YELLOW}[${T_NODES[$task_idx]}]${C_NC} nodes"
    echo -e "Executable binary is ${C_YELLOW}[${T_BINS[$task_idx]}]${C_NC}"
    echo -e "Topology file is ${C_YELLOW}[${T_PRMTOPS[$task_idx]}]${C_NC}"
    echo -e "Config file is ${C_YELLOW}[${T_CONFIGS[$task_idx]}]${C_NC}"
    echo -e "Start coordinates are in file ${C_YELLOW}[${T_COORDS[$task_idx]}]${C_NC}"
    echo -e "Output file is ${C_YELLOW}[${T_OUTPUTS[$task_idx]}]${C_NC}"
    echo -e "Restart will be written to file ${C_YELLOW}[${T_RESTARTS[$task_idx]}]${C_NC}"
    echo -e "Trajectories will be written to file ${C_YELLOW}[${T_TRAJS[$task_idx]}]${C_NC}"
    echo -e "MD information will be available in file ${C_YELLOW}[${T_INFOS[$task_idx]}]${C_NC}"

    if [[ "${T_COORDS[$task_idx]}" == "${T_RESTARTS[$task_idx]}" ]]
    then
        echo -e "${C_RED}WARNING: coordinates and restart files are the same! Original coordinates will be overwritten!${C_NC}" >&2
    fi

    echo -e "${C_BLUE}------${C_NC}"
    echo -n -e "Trying to save prepared command to ${C_YELLOW}[${DATAROOT%/}/${T_DIRS[$task_idx]}/runcmd.$$]${C_NC}... "

    # now we'll build final execution line...
    COMMAND="\"$AMBERROOT/bin/${T_BINS[$task_idx]}\" -O -i \"${T_CONFIGS[$task_idx]}\" -o \"${T_OUTPUTS[$task_idx]}\" -p \"${T_PRMTOPS[$task_idx]}\" -c \"${T_COORDS[$task_idx]}\" -r \"${T_RESTARTS[$task_idx]}\" -x \"${T_TRAJS[$task_idx]}\" -inf \"${T_INFOS[$task_idx]}\""

    # ...and store it in appropriate place
    echo "$COMMAND" 2> /dev/null > "${DATAROOT%/}/${T_DIRS[$task_idx]}/runcmd.$$"

    if [[ "$?" -eq 0 ]]
    then
        echo -e "${C_GREEN}ok${C_NC}"
    else
        echo -e "${C_RED}fail${C_NC}"
        let NUMERRORS++
    fi

    echo

    # add number of nodes and data directory for that task to runlist
    echo "${T_NODES[$task_idx]} ${DATAROOT%/}/${T_DIRS[$task_idx]}" >> "$RUNLIST"
done


# give user the last chance to fix anything
echo
echo -e "${C_YELLOW}$((NUMTASKS - NUMERRORS))/$NUMTASKS${C_NC} commands prepared successfully"
echo -e "If you've noticed any mistakes in current configuration press Ctrl+C for ${C_YELLOW}$SLEEPTIME${C_NC} seconds"
sleep $SLEEPTIME
echo
echo


# prepare SLURM command
CMD="sbatch -N $TOTALNODES -p $PARTITION -t $RUNTIME $AMBERTASK $$ $RUNTIME $DATAROOT"
echo "Command that will be run:"
echo -e "${C_YELLOW}$CMD${C_NC}"
echo
echo

# go to the scratch root and submit job
cd "${HOME}/_scratch"

TASKID=`$CMD | grep 'Submitted batch job' | awk '{print $NF}'`

if [[ "$?" -eq 0 ]]
then
    echo -e "Job submitted successfully. SLURM job ID is ${C_YELLOW}[$TASKID]${C_NC}"
else
    echo -e "${C_RED}ERROR: something wrong with job queueing! Check SLURM output.${C_NC}" >&2
    exit $E_RUN_FAIL
fi


# we're done here
exit 0