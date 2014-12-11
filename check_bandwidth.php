<?php
$ds_name[1] = "Traffic Mbps";
$opt[1] = " --vertical-label \"Mbps\" -b 1000 --title \"Interface Traffic for $hostname / $servicedesc\" ";
$def[1] = "DEF:var1=$RRDFILE[1]:$DS[5]:AVERAGE " ;
$def[1] .= "DEF:var2=$RRDFILE[2]:$DS[6]:AVERAGE " ;
$def[1] .= "AREA:var1#0000ff:\"in  \" " ;
$def[1] .= "GPRINT:var1:LAST:\"%7.2lf %Sb/s last\" " ;
$def[1] .= "GPRINT:var1:AVERAGE:\"%7.2lf %Sb/s avg\" " ;
$def[1] .= "GPRINT:var1:MAX:\"%7.2lf %Sb/s max\\n\" " ;
$def[1] .= "AREA:var2#00ff00:\"out \" " ;
$def[1] .= "GPRINT:var2:LAST:\"%7.2lf %Sb/s last\" " ;
$def[1] .= "GPRINT:var2:AVERAGE:\"%7.2lf %Sb/s avg\" " ;
$def[1] .= "GPRINT:var2:MAX:\"%7.2lf %Sb/s max\\n\" ";
if ($WARN[1] != "") {  
        $def[1] .= "HRULE:$WARN[5]#FFFF00:\"Warning ($WARN[5]Kbit/s)\" " ; 
}
if ($CRIT[1] != "") {  
        $def[1] .= "HRULE:$CRIT[5]#FF0000:\"Critical ($CRIT[5]Kbit/s)\\n\" " ; 
}
if ($WARN[1] != "") {  
        $def[1] .= "HRULE:$WARN[6]#FFFF00:\"Warning ($WARN[6]Kbit/s)\" " ; 
}
if ($CRIT[1] != "") {  
        $def[1] .= "HRULE:$CRIT[6]#FF0000:\"Critical ($CRIT[6]Kbit/s)\\n\" " ; 
}
?>

 
