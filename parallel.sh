#script to download lot of tables in parallel with Sqoop and write them to Hive

# Example of usage:
# ./sqoopTables.sh -d myDatabase2 -H myHiveDatabase3 -p 6 -q etl /tmp/foo
# the file (in that example: /tmp/foo) must contain on each line the name of a table you want to sqoop. If you want to sqoop 5 tables, you need 5 lines in your file
# your TODO: this #script is focused to SQLserver. Search the "sqoop import" line (in the middle of the script) and change the header of the URL appropriately. Also change in this line the user and password here.

# Documentation:
# https://community.hortonworks.com/articles/23602/sqoop-fetching-lot-of-tables-in-parallel.html

#### Default values:
# (configure here your default values. Those values can be overriden on the command line)
origServer=52.207.2.108 # The FQDN of the relational database you want to fetch (option: -o)
origDatabase=northwind                                           # The names of the database that contains the tables to fetch (option: -d)
hiveDatabase=grp2                                         # The name of the Hive database that will get the tables fetched (option: -H)
parallelism=4                                                    # The number of tables (sqoop processes) you want to download at the same time (option: -p)
queue=default                                                    # The queue used in Yarn (option: -q)
baseDir=/tmp/sqoopTables2                                         # Base directory where will be stored the log files (option: -b)
dirJavaGeneratedCode=/tmp/doSqoopTable2-`id -u`-tmp              # Directory for the java code generated by Sqoop (option: -c)
targetTmpHdfsDir=/user/miti/project_shellscript/sqooptables        # Temporary directory in HDFS to store downloaded data before moving it to Hive

# TODO: delete sqoop tmp directory after jobs ends

# argument: variable you want to be populated byt the value poped by the stack
function popStack(){
        : ${1?'Missing stack name'}

        # check if array not void
        local pointerStack=$(<$pointerStackFile)
        [ $pointerStack -ge $initialSizeStack ] && return 1

        eval "$1"=${listOfTables[$pointerStack]}

        (( pointerStack=$pointerStack+1))
        echo $pointerStack > $pointerStackFile
        return 0
}

function doSqoop(){
        local id=$1     # this id should be unique betwween all the instances of doSqoop
        local myVariable=tableFor_$id
        local logFileSummary=$databaseBaseDir/process_$id-summary.log
        local logFileRaw=$databaseBaseDir/process_$id-raw.log

        echo -e "\n\n############################# `date` Starting new execution [ $origDatabase -> $hiveDatabase ] #############################" >> $logFileSummary

        while true; do

                IFS="
                "

                # get the name of the next table to sqoop
                popStack $myVariable
                [ $? -ne 0 ] && break


                local myTable=${!myVariable// /_}

                echo "this is myTable $myTable"

                local myTableOrigin=${!myVariable}

                #echo "---------this is myTableOrigin $myTableOrigin"

                # in my current project, there were some special mapping to get the name of the Hive tables from the name of the SQLserver tables:
                #local origTable=`echo $myTable | sed -e 's/^su_/dbosu./' -e 's/^sc_/dbosc./' -e 's/^sm_/dbosm./' -e 's/^cm_/dbo./'`
                local origTable=$myTableOrigin

                echo "this is origTable $origTable"

                echo "[`date`] Creating the table $hiveDatabase.$myTable from the SQLserver table $origDatabase.$origTable" | tee -a $logFileSummary $logFileRaw

                # To fix bug for tables that have columns with spaces:
                # see: http://stackoverflow.com/questions/27572527/how-to-support-column-names-with-spaces-using-sqoop-import
                sqoop import --connect jdbc:mysql://$origServer:3306/$origDatabase --username=temp --password=temp --m 1 --outdir $dirJavaGeneratedCode --table $origTable --delete-target-dir --target-dir $targetTmpHdfsDir/$myTable --fields-terminated-by ',' --hive-import --create-hive-table --hive-table $hiveDatabase.$myTable >> $logFileRaw 2>> $logFileRaw

                echo "Tail of : $logFileRaw" >> $logFileSummary
                tail -6 $logFileRaw  >> $logFileSummary

                echo "tables sqooped and created $hiveDatabase.$myTable"

        done

        echo -e "\n############################# `date` Ending execution [ $origDatabase -> $hiveDatabase ] #############################" >> $logFileSummary
}

function usage() {
        echo -e "usage:\t`basename $0` [-b <report directory>] [-c <directory for java code>] [-d <source database] [-H <hive database>] [-o <source server>] [-p <parallelism>] [-q <queue>] <fileName>"
        echo -e "usage:\t`basename $0` -h"
        echo -e "\t\t\tthe file must contain on each line the name of a table you want to sqoop. If you want to sqoop 5 tables, you need 5 lines in your file"
        exit 0
}

while getopts "b:c:d:hH:o:p:q:" FLAG; do
  case $FLAG in
    b)  baseDir=$OPTARG
      ;;
    c)  dirJavaGeneratedCode=$OPTARG
      ;;
    d)  origDatabase=$OPTARG
      ;;
    h)  usage
      ;;
    H)  hiveDatabase=$OPTARG
      ;;
    o)  origServer=$OPTARG
      ;;
    p)  parallelism=$OPTARG
      ;;
    q)  queue=$OPTARG
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      usage
      ;;
  esac
done

shift $((OPTIND-1))  #This tells getopts to move on to the next argument.

# TODO: check if the argument is a file. If not, consider this is a list of table
IFS="
"
myFile=$1
[ "x$myFile" = "x" ] && usage
[ -f $myFile ] || usage

listOfTables=( `cat $myFile`)
initialSizeStack=${#listOfTables[@]}
pointerStack=0  # to know which element must be fetched next
pointerStackFile=/dev/shm/.sqoopTables_pointerStack_$$
echo 0 > $pointerStackFile

databaseBaseDir=$baseDir/$origDatabase-$hiveDatabase
[ -d $databaseBaseDir ] || mkdir -p $databaseBaseDir
for i in `seq $parallelism`; do
        sleep 0.1 # to avoid subprocesses to pop the stack at the same time
        (doSqoop $i) &
done

wait
rm -f $pointerStackFile

