#!/bin/bash

INTERVAL="1"  # update interval in seconds

script_name=$(basename $0)

#echo "Current script agruments: $@"

function usage ()
{
        echo
        echo "Usage: $script_name <interface_name> <measurenment time s> <warning mbit/s> <critical mbit/s> <total mbit/s>" 
        echo "Example:"
        echo "$script_name eth0 15 80 90 100"
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

if [ "$#" -ne 5 ]; then
	usage
        exit 3
fi

IF=$1
sec=$2
warn=$3
crit=$4
iface_speed=$5

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

bin_ps=`which ps`
bin_grep=`which grep`
bin_expr=`which expr`
bin_cat=`which cat`
bin_tac=`which tac`
bin_sort=`which sort`
bin_wc=`which wc`
bin_awk=`which awk`
bin_cut=`which cut`

if [ $(whoami) == "nrpe" ] ;then
   temp_dir=`$bin_grep nrpe /etc/passwd | $bin_cut -d: -f6`
else
   temp_dir=/tmp
fi

if ! [ -d $temp_dir ] ; then
   echo "temp dir $temp_dir not exist"
   exit 3 
fi

tmpfile_rx=$temp_dir/check_bandwidth_rx_"$IF"_"$$".tmp
tmpfile_tx=$temp_dir/check_bandwidth_tx_"$IF"_"$$".tmp
reverse_tmpfile_rx=$temp_dir/check_bandwidth_rx_reverse_"$IF"_"$$".tmp
reverse_tmpfile_tx=$temp_dir/check_bandwidth_tx_reverse_"$IF"_"$$".tmp
deltafile_rx=$temp_dir/check_bandwidth_rx_delta_"$IF"_"$$".tmp
deltafile_tx=$temp_dir/check_bandwidth_tx_delta_"$IF"_"$$".tmp

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

START_TIME=`date +%s`
n=0
while [ $n -lt $sec ]
do
	$bin_cat $sysrx_file >> $tmpfile_rx
	$bin_cat $systx_file >> $tmpfile_tx
	sleep $INTERVAL
	let "n = $n + 1"
done
FINISH_TIME=`date +%s`
$bin_cat $tmpfile_rx | $bin_sort -nr > $reverse_tmpfile_rx
$bin_cat $tmpfile_tx | $bin_sort -nr > $reverse_tmpfile_tx

while read line;
do
	if [ -z "$RBYTES" ];
	then
		RBYTES=`cat $sysrx_file`
		$bin_expr $RBYTES - $line >> $deltafile_rx;
	else
		$bin_expr $RBYTES - $line >> $deltafile_rx;
	fi
	RBYTES=$line
done < $reverse_tmpfile_rx

while read line;
do
	if [ -z "$TBYTES" ];
	then
		TBYTES=`cat $systx_file`
		$bin_expr $TBYTES - $line >> $deltafile_tx;
	else
		$bin_expr $TBYTES - $line >> $deltafile_tx;
	fi
	TBYTES=$line
done < $reverse_tmpfile_tx

while read line;
do
	SUM_RBYTES=`$bin_expr $SUM_RBYTES + $line`
done < $deltafile_rx

while read line;
do
	SUM_TBYTES=`$bin_expr $SUM_TBYTES + $line`
done < $deltafile_tx

let "DURATION = $FINISH_TIME - $START_TIME"
let "RBITS_SEC = ( $SUM_RBYTES * 8 ) / $DURATION"
let "TBITS_SEC = ( $SUM_TBYTES * 8 ) / $DURATION"

#echo -e "RBITS_SEC=$RBITS_SEC\nTBITS_SEC=$TBITS_SEC\nwarn_kbits=$warn_kbits\ncrit_kbits=$crit_kbits\n"

if [ $RBITS_SEC -lt $warn_kbits -a $TBITS_SEC -lt $warn_kbits ]
then
	data_output_r=`echo "$RBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
	data_output_t=`echo "$TBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
	percent_output_r=`echo "$RBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
	percent_output_t=`echo "$TBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
	nagvis_perfdata_r="InUsage=$percent_output_r%;$warn_kbits;$crit_kbits"
	nagvis_perfdata_t="OutUsage=$percent_output_t%;$warn_kbits;$crit_kbits"
	pnp4nagios_perfdata_r="in=$RBITS_SEC;$warn_kbits;$crit_kbits"
	pnp4nagios_perfdata_t="in=$TBITS_SEC;$warn_kbits;$crit_kbits"
	output="IN $data_output_r Mbit/s OUT $data_output_t Mbit/s - OK, period $DURATION sec | $nagvis_perfdata_r $nagvis_perfdata_t inBandwidth="$data_output_r"Mbs outBandwidth="$data_output_t"Mbs $pnp4nagios_perfdata_r $pnp4nagios_perfdata_t"
            exitstatus=0
elif [ $RBITS_SEC -ge $warn_kbits -a $RBITS_SEC -le $crit_kbits ] || [ $TBITS_SEC -ge $warn_kbits -a $TBITS_SEC -le $crit_kbits ];
then
	data_output_r=`echo "$RBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
	data_output_t=`echo "$TBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
	percent_output_r=`echo "$RBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
	percent_output_t=`echo "$TBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
	nagvis_perfdata_r="InUsage=$percent_output_r%;$warn_kbits;$crit_kbits"
	nagvis_perfdata_t="OutUsage=$percent_output_t%;$warn_kbits;$crit_kbits"
	pnp4nagios_perfdata_r="in=$RBITS_SEC;$warn_kbits;$crit_kbits"
	pnp4nagios_perfdata_t="in=$TBITS_SEC;$warn_kbits;$crit_kbits"
	output="IN $data_output_r Mbit/s OUT $data_output_t Mbit/s WARNING! period $DURATION sec | $nagvis_perfdata_r $nagvis_perfdata_t inBandwidth="$data_output_r"Mbs outBandwidth="$data_output_t"Mbs $pnp4nagios_perfdata_r $pnp4nagios_perfdata_t"
	exitstatus=1
elif [ $RBITS_SEC -gt $crit_kbits -o $TBITS_SEC -gt $crit_kbits ]
then
	data_output_r=`echo "$RBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
	data_output_t=`echo "$TBITS_SEC 1000000" | $bin_awk '{ printf ("%.2f", $1/$2); }'`
	percent_output_r=`echo "$RBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
	percent_output_t=`echo "$TBITS_SEC $iface_speed_kbits 100" | $bin_awk '{ printf ("%.2f", $1/$2*$3); }'`
	nagvis_perfdata_r="InUsage=$percent_output_r%;$warn_kbits;$crit_kbits"
	nagvis_perfdata_t="OutUsage=$percent_output_t%;$warn_kbits;$crit_kbits"
	pnp4nagios_perfdata_r="in=$RBITS_SEC;$warn_kbits;$crit_kbits"
	pnp4nagios_perfdata_t="in=$TBITS_SEC;$warn_kbits;$crit_kbits"
	output="IN $data_output_r Mbit/s OUT $data_output_t Mbit/s CRITICAL! period $DURATION sec | $nagvis_perfdata_r $nagvis_perfdata_t inBandwidth="$data_output_r"Mbs outBandwidth="$data_output_t"Mbs $pnp4nagios_perfdata_r $pnp4nagios_perfdata_t"
	exitstatus=2
else
	output="unknown status"
	exitstatus=3
fi

rm -f $tmpfile_rx
rm -f $reverse_tmpfile_rx
rm -f $deltafile_rx
rm -f $tmpfile_tx
rm -f $reverse_tmpfile_tx
rm -f $deltafile_tx

echo "$output"
exit $exitstatus

