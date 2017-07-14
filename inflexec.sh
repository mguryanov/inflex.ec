#!/bin/bash

: << 'readme'

Supported managment commands:

> SELECT INTO
> SHOW [DATABASES|MEASUREMENTS|FIELDS_KEYS|TAGS|TAGS_VALUES]
> SELECT
> DELETE
> DROP

readme




docker_exec() {

DO=$1
UN=$2
PS=$3
DB=$4
CMD=$5
MS=$6

    OUTPUT="$(sudo docker exec -it influxdb influx \
               -execute "$DO" \
               -username "$UN" \
               -password "$PS" \
               -database "$DB" \
               -format=json -pretty \
               | jq -r '.results[]|select(.series!=null).series[].values[]|.[]' )" > /dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        echo "failed docker execute command '$DO'"
        exit 1
    fi

    case $CMD in
        ESHOW)
            [[ ! -z $OUTPUT ]] && break
            printf "$MS\n"
        ;;
        SHOW)
            [[ ${#OUTPUT} -eq 0 ]] && break
            printf "$DO\n"
            arr=($OUTPUT)
            for (( i=0; i < ${#arr[@]} ; ++i ))
            do
                [[ ${arr[$i]} =~ ([0-9]*)\.([0-9]*) ]];
                a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
                [[ ${#BASH_REMATCH[2]} -eq 5 ]] && (( b*=10000 ))
                [[ ${#BASH_REMATCH[2]} -eq 6 ]] && (( b*=1000 ))
                [[ ${#BASH_REMATCH[2]} -eq 7 ]] && (( b*=100 ))
                dt=$( date +%FT%XZ --date=@${a}${b} )
                (( ++i ))
                printf "$dt\t${arr[$i]}\n";
            done
        ;;
        *)
            printf "$DO\n"
            echo ${OUTPUT//}
        ;;
    esac

}




PROGNAME=$0
declare -a CMDS
declare -a NDS # Named Data Source
i=0 # cmd node index




while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -u|--user)
    U_NAME="$2"
    shift
    ;;
    -p|--password)
    PSWD="$2"
    shift
    ;;
    -c|--command)
    CMDS[$i]="$2"
    (( i+=1 ))
    shift
    ;;
    -d|--database)
    DB[$i]="$2"
    shift
    ;;
    -x|--regexp)
    REGEXP[$i]="$2"
    shift
    ;;
    -vx|--vregexp)
    VREGEXP[$i]="$2"
    shift
    ;;
    -f|--field)
    FIELDS[$i]="$2"
    shift
    ;;
    -t|--bytag)
    BYTAG[$i]="$2"
    shift
    ;;
    -g|--groupby)
    GROUPBY[$i]="$2"
    shift
    ;;
    -r|--retention)
    RETENTION[$i]="$2"
    shift
    ;;
    -m|--measure)
    MEASURE[$i]="$2"
    shift
    ;;
    --prefix)
    PREFIX="$2"
    shift
    ;;
    --postfix)
    POSTFIX="$2"
    shift
    ;;
    --period)
    PERIOD[$i]="$2"
    shift
    ;;
    --time-start)
    STARTT[$i]="$2"
    shift
    ;;
    --time-stop)
    STOPT[$i]="$2"
    shift
    ;;
    --time-split)
    SPLITT[$i]="$2"
    shift
    ;;
    *)
    shift # unknown option
    ;;
esac
shift
done



UNAME=${UNAME:-$IFX_USER}
PSWD=${PSWD:-$IFX_PSWD}
DB[0]=${DB[0]:-$IFX_DB}



if [[ -z $UNAME || -z $PSWD || -z ${CMDS[0]} ]]
then
    echo -e "using like:\n"                             \
         $PROGNAME                                      \
         "-u/--user NAME"                               \
         "-p/--password PSWD"                           \
         "-c/--command DROP|INTO\n"                     \
         "\t [-d/--database DBNAME]\n"                  \
         "\t [--regexp /^cpu_/]\n"                      \
         "\t [--retention 'DEFAULT'\n"                  \
         "\t [--measure 'snmp']\n"                      \
         "\t [--prefix PREFIX_MEASUREMENT]\n"           \
         "\t [--postfix POSTFIX_MEASUREMENT]"
    exit 0
fi



# show_measurements_stmt = "SHOW MEASUREMENTS" [ with_measurement_clause ] [ where_clause ] [ limit_clause ] [ offset_clause ]
# show_tag_keys_stmt = "SHOW TAG KEYS" [ from_clause ] [ where_clause ] [ group_by_clause ] [ limit_clause ] [ offset_clause ]
# show_tag_values_stmt = "SHOW TAG VALUES" [ from_clause ] with_tag_clause [ where_clause ] [ group_by_clause ] [ limit_clause ] [ offset_clause ]
# show_databases_stmt = "SHOW DATABASES"
# show_field_keys_stmt = "SHOW FIELD KEYS" [ from_clause ]

# delete_stmt = "DELETE" ( from_clause | where_clause | from_clause where_clause )
# examples :
# DELETE FROM "cpu" WHERE time < '2000-01-01T00:00:00Z'
# DELETE WHERE time < '2000-01-01T00:00:00Z'

# drop_database_stmt = "DROP DATABASE" db_name
# drop_measurement_stmt = "DROP MEASUREMENT" measurement
# drop_series_stmt = "DROP SERIES" ( from_clause | where_clause | from_clause where_clause )

# select_stmt = "SELECT" fields from_clause [ into_clause ] [ where_clause ] [ group_by_clause ] [ order_by_clause ] [ limit_clause ] [ offset_clause ] [ slimit_clause ] [ soffset_clause ]

show_stmt="SHOW"
select_stmt="SELECT"
drop_stmt="DROP"
delete_stmt="DELETE"

# with_measurement_clause = "WITH MEASUREMENT" ( "=" measurement | "=~" regex_lit )
# with_tag_clause = "WITH KEY" ( "=" tag_key | "!=" tag_key | "=~" regex_lit | "IN (" tag_keys ")"  )

from_clause="FROM"
into_clause="INTO"
where_clause="WHERE"

with_measurement_clause="WITH MEASUREMENT"
with_tag_clause="WITH KEY"
limit_clause="LIMIT"
group_by_clause="GROUP BY"


i=0 # cmd node index

for CMD in "${CMDS[@]}"
do

    case $CMD in
    # SHOW
        MS|MEASURES)
            stmt="$show_stmt MEASUREMENTS"
            if [[ ! -z ${REGEXP[$i]} ]]; then
                stmt+=" $with_measurement_clause =~ ${REGEXP[$i]}"
            fi
        ;;
        FD|FIELDS)
            stmt="$show_stmt FIELD KEYS"
            if [[ ! -z ${MEASURE[$i]} ]]; then
                stmt+=" $from_clause ${MEASURE[$i]}"
            fi
        ;;
        DB)
            stmt="$show_stmt DATABASES"
        ;;
        TG|TAGS)
            stmt="$show_stmt TAG VALUES"
            if [[ ! -z ${MEASURE[$i]} ]]; then
                stmt+=" $from_clause ${MEASURE[$i]}"
            else
                echo "failed TAGS: --measure option requered"
                exit 1
            fi
            if [[ ! -z ${REGEXP[$i]} ]]; then
                stmt+=" $with_tag_clause =~ ${REGEXP[$i]}"
            elif [[ ! -z ${VREGEXP[$i]} ]]; then
                stmt+=" $with_tag_clause !~ ${VREGEXP[$i]}"
            else
                echo "failed TAGS: --regexp or --vregexp option requered"
                exit 1
            fi
        ;;
        KS|KEYS)
            stmt="$show_stmt TAG KEYS"
            if [[ ! -z ${MEASURE[$i]} ]]; then
                stmt+=" $from_clause ${MEASURE[$i]}"
            fi
        ;;
    # DROP
        DRB|DROPDB)
            stmt="$drop_stmt DATABASE"
            if [[ ! -z ${DB[$i]} ]]; then
                stmt+=" ${DB[$i]}"
            else
                echo "failed DROPDB: --database option requered"
                exit 1
            fi
        ;;
        DRM|DROPM)
            stmt="$drop_stmt MEASUREMENT"
            if [[ ! -z ${MEASURE[$i]} ]]; then
                stmt+=" ${MEASURE[$i]}"
            else
                echo "failed DROPM: --measure-from option requered"
                exit 1
            fi
        ;;
        DRS|DROPS)
            stmt="$drop_stmt SERIES"
            if [[ ! -z ${MEASURE[$i]} ]]; then
                stmt+=" $from_clause ${MEASURE[$i]}"
            else
                echo "failed DROPS: --measure-from option requered"
                exit 1
            fi
        ;;
    # INTO
        INTO)
            p="$(( $i-1 ))"
            if [[ -z ${FIELDS[$i]} ]]; then
                echo "failed INTO: --fields option requered"
                exit 1
            fi
            stmt="$select_stmt ${FIELDS[$i]}"
            if [[ -z ${MEASURE[$i]} || ${MEASURE[$i]} != "{}" ]]; then
                echo "failed INTO: to --measure's options requered"
                exit 1
            fi
            stmt+=" $into_clause \"${DB[0]}\".\"${RETENTION[$i]:-"default"}\".${PREFIX}${MEASURE[$i]}${POSTFIX}"
            stmt+=" $from_clause \"${DB[0]}\".\"${RETENTION[$p]:-"default"}\".${MEASURE[$i]}"
            if [[ -z ${PERIOD[$i]}  &&
                  -z ${STARTT[$i]}  &&
                  -z ${STOPT[$i]} ]]; then
                break
            fi
            stmt+=" $where_clause"
            complex=0
            if [[ ! -z ${PERIOD[$i]} ]]; then
                stmt+=" time >= now() - ${PERIOD[$i]}"
                (( complex++ ))
            fi
            if [[ ! -z ${STARTT[$i]} || ! -z ${SPLITT[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" time >= '[)'"
                (( complex++ ))
            fi
            if [[ ! -z ${STOPT[$i]} && -z ${SPLITT[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" time <= '(]'"
            fi
            if [[ ! -z ${SPLITT[$i]} ]]; then
                stmt+=" AND"
                stmt+=" time < '(]'"
            fi
:<<debug
debug
            stmt+=" $group_by_clause"
            if [[ ! -z ${GROUPBY[$i]} ]]; then
                [[ ${GROUPBY[$i]} =~ (.*)([0-9]+[mshd])(.*) ]] \
                    && stmt+=" ${BASH_REMATCH[1]}time(${BASH_REMATCH[2]})${BASH_REMATCH[3]}"
            else
                stmt+=" * "
            fi
        ;;
        # SHOW
        SHOW|ESHOW)
            p="$(( $i-1 ))"
            if [[ -z ${FIELDS[$i]} ]]; then
                echo "failed SHOW: --fields option requered"
                exit 1
            fi
            stmt="$select_stmt ${FIELDS[$i]}"
            if [[ -z ${MEASURE[$i]} || ${MEASURE[$i]} != "{}" ]]; then
                echo "failed SHOW: to --measure's options requered"
                exit 1
            fi
            stmt+=" $from_clause \"${DB[0]}\".\"${RETENTION[$p]:-"default"}\".${MEASURE[$i]}"
            if [[ -z ${PERIOD[$i]}  &&
                  -z ${STARTT[$i]}  &&
                  -z ${STOPT[$i]} ]]; then
                break
            fi
            stmt+=" $where_clause"
            complex=0
            if [[ ! -z ${PERIOD[$i]} ]]; then
                stmt+=" time >= now() - ${PERIOD[$i]}"
                (( complex++ ))
            fi
            if [[ ! -z ${STARTT[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" time >= '${STARTT[$i]}'"
                (( complex++ ))
            fi
            if [[ ! -z ${STOPT[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" time <= '${STOPT[$i]}'"
            fi
:<<debug
debug
            stmt+=" $group_by_clause"
            if [[ ! -z ${GROUPBY[$i]} ]]; then
                [[ ${GROUPBY[$i]} =~ (.*)([0-9]+[mshd])(.*) ]] \
                    && stmt+=" ${BASH_REMATCH[1]}time(${BASH_REMATCH[2]})${BASH_REMATCH[3]}"
            fi
        ;;
    # DELETE
        DLT|DELETE)
            stmt="$delete_stmt "
            if [[ ! -z ${MEASURE[$i]} ]]; then
                stmt+=" $from_clause \"${DB[0]}\".\"${RETENTION[$i]:-"default"}\".${PREFIX}${MEASURE[$i]}${POSTFIX}"
            fi
            if [[ -z ${PERIOD[$i]}  &&
                  -z ${STARTT[$i]}  &&
                  -z ${REGEXP[$i]}  &&
                  -z ${VREGEXP[$i]} &&
                  -z ${BYTAG[$i]} ]]; then
                break
            fi
:<<debug
debug
            stmt+=" $where_clause"
            complex=0
            if [[ ! -z ${PERIOD[$i]} ]]; then
                stmt+=" time >= now() - ${PERIOD[$i]}"
                (( complex++ ))
            fi
            if [[ ! -z ${STARTT[$i]} || ! -z ${SPLITT[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" time >= '[)'"
                (( complex++ ))
            fi
            if [[ ! -z ${STOPT[$i]} && -z ${SPLITT[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" time <= '(]'"
            fi
            if [[ ! -z ${SPLITT[$i]} ]]; then
                stmt+=" AND"
                stmt+=" time < '(]'"
            fi
            if [[ ! -z ${REGEXP[$i]} && ! -z ${BYTAG[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" ${BYTAG[$i]} =~ ${REGEXP[$i]}"
            elif [[ ! -z ${VREGEXP[$i]} && ! -z ${BYTAG[$i]} ]]; then
                [[ $complex -gt 0 ]] && stmt+=" AND"
                stmt+=" ${BYTAG[$i]} !~ ${VREGEXP[$i]}"
            else
                echo "failed DEL: --bytag and --regexp or --vregexp options required"
                exit 1
            fi
            ;;

        *)
        echo "sorry, unknown command $CMD"
        exit 0
        ;;
    esac

    EXECUTES[$i]="$stmt"
    (( i+=1 ))

done # cycle


FETCH=${EXECUTES[0]}
RESPONSE="$(sudo docker exec -it influxdb influx \
                -execute "$FETCH" \
                -username "$UNAME" \
                -password "$PSWD" \
                -database "${DB[0]}" \
                -format=json -pretty \
                | jq -r '.results[]|select(.series!=null).series[].values[]|.[]' )" > /dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo "failed docker execute command '$FETCH'"
    exit 1
fi

RESULTS=($RESPONSE)

# measurements inverse-match
if [[ ! -z ${VREGEXP[0]} ]]; then
    MATCH=${VREGEXP[0]//\//}
    RANGE=${#RESULTS[@]}
    for (( i=0; i <= RANGE; ++i )); do
        if [[ ${RESULTS[$i]} =~ $MATCH ]]; then
            unset RESULTS[$i]
        fi
    done
fi


if [[ ${#EXECUTES[@]} -lt 2 ]]; then
    for r in ${RESULTS[@]}; do
        echo $r
    done
    exit 0
fi

for RESULT in ${RESULTS[@]}; do

    COUNT=1
    INC_TS=1
    RESIDUE=0

    PRE1=${EXECUTES[1]//\{\}/$RESULT}

    [[ -z ${STOPT[1]} ]] \
        && STOP_TS=$(date +%s) || STOP_TS=$(date +%s --date="${STOPT[1]}")
    [[ -z ${STARTT[1]} ]] \
        && START_TS=$(date +%s) || START_TS=$(date +%s --date="${STARTT[1]}")

    if [[ ! -z ${SPLITT[1]} ]]; then
        if [[ ${SPLITT[1]} =~ ([0-9]*)([dhms]) ]]; then
            case ${BASH_REMATCH[2]} in
                d) k=86400;;
                h) k=3600;;
                m) k=60;;
                s) k=1;;
                *) k=0;;
            esac
            INC_TS=$(( ${BASH_REMATCH[1]} * $k ))
        fi
        if [[ $START_TS -gt $STOP_TS ]]; then
            echo "failed START time value: ${STARTT[1]}"
            exit 1
        fi
        RESIDUE=$(( ( $STOP_TS - $START_TS ) % $INC_TS ))
        COUNT=$(( ( $STOP_TS - $START_TS ) / $INC_TS ))
        [[ $RESIDUE -gt 0 ]] && (( ++COUNT ))
    fi
    for (( n=0; n < $COUNT; ++n ))
    do
        OFFSET_START=$(( $n * $INC_TS + $START_TS ))
        if [[ $n -eq $COUNT && $RESIDUE ]]; then
            OFFSET_STOP=$(( $OFFSET_START + $RESIDUE ))
        else
            OFFSET_STOP=$(( $OFFSET_START + $INC_TS ))
        fi

        PRE2=${PRE1//\[\)/$( date +%FT%XZ --date=@$OFFSET_START )}
        DO=${PRE2//\(\]/$( date +%FT%XZ --date=@$OFFSET_STOP )}

       docker_exec "$DO" $UNAME $PSWD ${DB[0]} ${CMDS[1]} $RESULT
    done;
done




exit 0
