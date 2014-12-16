#!/bin/bash

INTERVAL="1"  # update interval in seconds

script_name=$(basename $0)

function usage ()
{
        echo
        echo "Usage: $script_name [-i interface_name] [-t measurenment_time sec] [-w warning mbit/s] [-c critical mbit/s] [-s interface speed mbit/s]" 
        echo "Example:"
        echo "$script_name -i eth0 -t 15 -w 80 -c 90 -s 100"
}

function check_argument()
{
        echo $1 | egrep "^[0-9]+$" > /dev/null
        if [ $? -ne 0 ] ; then
                echo "argument: $1"
                echo "positive number is required"
                usage
                exit 3
        fi
}

argcounter=0
while getopts "i:t:w:c:s:" arg; do
	case $arg in
		i)
		IF=$OPTARG
		((argcounter++))
		;;
		t)
		sec=$OPTARG
		((argcounter++))
		;;
		w)
		warn=$OPTARG
		((argcounter++))
		;;
		c)
		crit=$OPTARG
		((argcounter++))
		;;
		s)
		iface_speed=$OPTARG
		((argcounter++))
		;;
		*)
		usage
		exit 3
		;;
	esac
done

# echo "Current script agruments: $@"

if [ "$argcounter" -ne 5 ]; then
	echo "missing arguments"
	usage
        exit 3
fi

#echo -e "IF=$IF\nsec = $sec\nwarn = $warn\ncrit = $crit\niface_speed = $iface_speed\n"

check_argument $sec
check_argument $warn
check_argument $crit
check_argument $iface_speed

if [ $sec -le 0 ] ; then
	echo "argmunet: $sec"
	echo "number of seconds have to be greather than 0"
	usage
	exit 3
fi

if [ $warn -ge $crit ] ; then
	echo "argmunets: $warn $crit"
	echo "warning value can't be greather than critical value"
	usage
	exit 3
fi

if [ $crit -gt $iface_speed ] ; then
	echo "argmunets: $crit $iface_speed"
	echo "critical value can't be greather than interface speed"
	usage
	exit 3
fi

bin_expr=`which expr`
bin_cat=`which cat`
bin_awk=`which awk`
bin_head=`which head`
bin_tail=`which tail`

if [ $(whoami) == "nrpe" ] ;then
   temp_dir=/var/run/nrpe
else
   temp_dir=/tmp
fi

if ! [ -d $temp_dir ] ; then
   echo "temp dir $temp_dir not exist"
   exit 3 
fi

tmpfile_rx=$temp_dir/check_bandwidth_rx_"$IF"_"$$".tmp
tmpfile_tx=$temp_dir/check_bandwidth_tx_"$IF"_"$$".tmp

touch $tmpfile_rx
if ! [ -f $tmpfile_rx ] ; then
	echo "can't create files in temp dir $temp_dir"
	exit 3
fi

warn_kbits=`$bin_expr $warn '*' 1000000`
crit_kbits=`$bin_expr $crit '*' 1000000`
iface_speed_kbits=`$bin_expr $iface_speed '*' 1000000`

sysrx_file=/sys/class/net/"$IF"/statistics/rx_bytes
systx_file=/sys/class/net/"$IF"/statistics/tx_bytes

if ! [ -f $sysrx_file ] ; then
        echo "file $sysrx_file not exist"
	echo "check is $IF interface exist"
        exit 3
fi

if ! [ -f $systx_file ] ; then
        echo "file $sysrx_file not exist"
	echo "check is $IF interface exist"
        exit 3
fi

$bin_cat $sysrx_file >> $tmpfile_rx
$bin_cat $systx_file >> $tmpfile_tx
sleep $sec
$bin_cat $sysrx_file >> $tmpfile_rx
$bin_cat $systx_file >> $tmpfile_tx

RBYTES_FIRST=`$bin_head -n 1 $tmpfile_rx`
RBYTES_LAST=`$bin_tail -n 1 $tmpfile_rx`
TBYTES_FIRST=`$bin_head -n 1 $tmpfile_rx`
TBYTES_LAST=`$bin_tail -n 1 $tmpfile_rx`

SUM_RBYTES=`$bin_expr $RBYTES_LAST - $RBYTES_FIRST`
SUM_TBYTES=`$bin_expr $TBYTES_LAST - $TBYTES_FIRST`

DURATION=$sec
let "RBITS_SEC = ( $SUM_RBYTES * 8 ) / $DURATION"
let "TBITS_SEC = ( $SUM_TBYTES * 8 ) / $DURATION"

#echo -e "RBITS_SEC=$RBITS_SEC\nTBITS_SEC=$TBITS_SEC\nwarn_kbits=$warn_kbits\ncrit_kbits=$crit_kbits\n"

data_output_r=`echo "$RBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
data_output_t=`echo "$TBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
percent_output_r=`echo "$RBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
percent_output_t=`echo "$TBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
nagvis_perfdata_r="InUsage=$percent_output_r%;$warn_kbits;$crit_kbits"
nagvis_perfdata_t="OutUsage=$percent_output_t%;$warn_kbits;$crit_kbits"
pnp4nagios_perfdata_r="in=$RBITS_SEC;$warn_kbits;$crit_kbits"
pnp4nagios_perfdata_t="in=$TBITS_SEC;$warn_kbits;$crit_kbits"

if [ $RBITS_SEC -lt $warn_kbits -a $TBITS_SEC -lt $warn_kbits ]
then
	output="IN $data_output_r Mbit/s OUT $data_output_t Mbit/s - OK, period $DURATION sec | $nagvis_perfdata_r $nagvis_perfdata_t inBandwidth="$data_output_r"Mbs outBandwidth="$data_output_t"Mbs $pnp4nagios_perfdata_r $pnp4nagios_perfdata_t"
	exitstatus=0
elif [ $RBITS_SEC -ge $warn_kbits -a $RBITS_SEC -le $crit_kbits ] || [ $TBITS_SEC -ge $warn_kbits -a $TBITS_SEC -le $crit_kbits ];
then
	output="IN $data_output_r Mbit/s OUT $data_output_t Mbit/s WARNING! period $DURATION sec | $nagvis_perfdata_r $nagvis_perfdata_t inBandwidth="$data_output_r"Mbs outBandwidth="$data_output_t"Mbs $pnp4nagios_perfdata_r $pnp4nagios_perfdata_t"
	exitstatus=1
elif [ $RBITS_SEC -gt $crit_kbits -o $TBITS_SEC -gt $crit_kbits ]
then
	output="IN $data_output_r Mbit/s OUT $data_output_t Mbit/s CRITICAL! period $DURATION sec | $nagvis_perfdata_r $nagvis_perfdata_t inBandwidth="$data_output_r"Mbs outBandwidth="$data_output_t"Mbs $pnp4nagios_perfdata_r $pnp4nagios_perfdata_t"
	exitstatus=2
else
	output="unknown status"
	exitstatus=3
fi

rm -f $tmpfile_rx
rm -f $tmpfile_tx

echo "$output"
exit $exitstatus

