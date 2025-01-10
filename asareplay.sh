#!/bin/bash
# This is a script to automate packet replay on ASA/FTD.
# Version 1
cat << EOF
To run this script following programs needs to be installed

tcpreplay
tcprewrite
tshark
mergecap

tcpreplay and tcprewrite are part of tcpreplay distribution.
tshark and mergecap part of the Wireshark distribution.
If you do not have these installed, press CTRL+C and install these first.

Press any key to continue
EOF
read

ROOT_UID=0 	      # Only users with $UID 0 have root privileges.
E_NOTROOT=87          # Non-root exit error.
E_INVALIDPROTOCOl=90  # When user enters a protocol other than tcp or udp.
E_NOFILE=91           # Packet capture file does not exist.
E_INVALIDOPTION=92    # User did not give any option to filter pcaps.
E_INVALIDINTERFACE=93 # User entered invalid interface.
E_INVALIDMAC=94       # User entered invalid MAC address.
E_TSHARK_INVALID=95   # User entered invalid tshark parameter
E_TCPREWRITE_INVALID=96 # User entered invalid tcprewrite parameter
E_TCPREPLAY_INVALID=97  # User entered invalid tcpreplay parameter
E_MERGECAP_INVALID=98 #Invalid mergecap parameter
E_EMPTYPCAP=100 # Resulting file is empty

# Variables are better than hard-coded values.
IP_DST="ip.dst"
IP_SRC="ip.src"
SRC_PORT="srcport"
DST_PORT="dstport"
TSHARK_TEMP_PCAP="temp.pcap"
minimumsize=25

# Run as root, of course.
if [ "$UID" -ne  "$ROOT_UID" ]
then
  echo "Must be root to run this script."
  exit $E_NOTROOT
fi  

#User options
# Text inside EOF is multiline echo
cat << EOF
To Replay Unidirectional UDP or TCP Traffic Press 1. 
To Replay Bidirectional UDP or TCP Traffic Press 2. 
EOF

read USER_OPTION


# Function userinput which gets input from the user such as Source/Destination IP address, ports, protocol, local inteface and formats input and does validation.
userinput()

{
	
# Text inside EOF is multiline echo
cat << EOF
Enter the name if the interface that you need to use to replay the packets. 
An example if the list is the following:

lo : 127.0.0.1
lo : ::1
ens192 : 192.168.1.38
ens192 : 2001:890:1:1::100
ens192 : fe80::9277:842e:d663:1481
virbr0 : 192.168.122.1

Valid options can be ens192 or virbr0.

Following is the list of availble interfaces on this machine.
EOF

ip -o addr | awk '{split($4, a, "/"); print $2" : "a[1]}' # This command output interfaces on local machine with IP addresses for user to choose.
echo ""
read INTERFACE
#echo $INTERFACE
#Check if the interface is valid.
ifconfig $INTERFACE > /dev/null || exit $E_INVALIDINTERFACE
SOURCE_MAC=$( ifconfig $INTERFACE   | awk '/ether/{print $2}')  # This command get the MAC address of the local interface which user entered.
							      
#echo $SOURCE_MAC
echo ""
echo "Enter the name of the pcap file, enter full path name if file is not in currrent working directory"
read PCAP
#echo $PCAP
if [ ! -f $PCAP ]
   then
	   echo "Capture File not found"
	   exit $E_NOFILE
fi # Check if capture file exists.

prefix=temp
suffix=$(date +%s)  # The "+%s" option to 'date' is GNU-specific.
filename=$prefix.$suffix.PCAP

echo "Temporary filename = $filename"
# To handle linux cooked capture
tcprewrite --dlt=enet -i $PCAP -o $filename
mv $filename $PCAP

echo ""
echo "Please enter minimum one option from Source IP, Destination IP, Source Port, Destination Port."
echo ""

echo "Enter the Source IP address or subnet in CIDR notation of the flow that needs to be replayed. See examples below"
echo "Single host enter 10.1.1.1, subnet enter 10.1.1.0/24, two subnets enter CIDR separated by a space 10.1.1.0/24 192.168.1.0/24."
echo "If you do not want to filter by Source IP address leave it blank and press enter."

echo "HINT: To see the packet details on CLI, use the command 'tshark -r file.pcap', where file.pcap is capture file name"
echo ""
read SOURCE_IP
#echo $SOURCE_IP
echo ""

echo "Enter the Destination IP address or subnet in CIDR notation of the flow that needs to be replayed. See examples below".
echo "Single host enter 10.1.1.1, subnet enter 10.1.1.0/24, two subnets enter CIDR separated by a space 10.1.1.0/24 192.168.1.0/24."
echo "If you do not want to filter by Destination IP address leave it blank and press enter."
echo ""
read DEST_IP
#echo $DEST_IP
echo ""

echo "Enter the transport layer protocol valid option for this script are TCP and UDP "
echo ""
read PROTO
PROTO=${PROTO,,}
#echo $PROTO
echo ""

# Check if the protocol is TCP or UDP
if [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]]
then 
	:	
else
	echo "Please enter tcp or udp as protocol"
	exit  $E_INVALIDPROTOCOl
fi # Check if protocol entered is tcp or udp.



echo "Enter the source port number of the flow that needs to be replayed, e.g if the protocol is TCP, any valid wireshark filter for tcp.src can be used." 
echo "If you do not want to filter by Source port leave it blank and press enter."
echo ""
read SOURCE_PORT
#echo $SOURCE_PORT
echo ""

echo "Enter the Destination port number of the flow that needs to be replayed, e.g if the protocol is TCP, any valid wireshark filter for tcp.dst can be used." 
echo "If you do not want to filter by destination port leave it blank and press enter."
echo ""
read DEST_PORT
#echo $DEST_PORT
echo ""

# Check if the user entered at least one option
if [[ -z "$SOURCE_IP" && -z "$DEST_IP" && -z "$SOURCE_PORT"  && -z "$DEST_PORT" ]]
	then 
		echo "Please enter at least one option, from Source IP, Destination IP, Source Port, Destination Port."
		exit $E_INVALIDOPTION
fi

echo "If VLAN ID needs to be deleted or of traces do not contain VLAN ID enter 1"
echo "If VLAN ID needs to be preserved enter 2"
echo ""
read VLANID
#echo $VLANID
if [[ "$VLANID" == "1" || "$VLANID" == "2" ]]
then
	:
                               
else     
	echo "Please enter valid VLAN ID option"
        exit  $E_INVALIDVLANID
fi # Check if VLAN ID option is valid.

if [ "$SOURCE_IP" == "" ]
then 
	SOURCE_IP="0.0.0.0..255.255.255.255"
fi

if [ "$DEST_IP" == "" ]
then 
	DEST_IP="0.0.0.0..255.255.255.255"
fi

if [[ "$SOURCE_PORT" == "" && "$PROTO" = "tcp" ]]
then 
	SOURCE_PORT="0..65535"
fi

if [[ "$SOURCE_PORT" == "" && "$PROTO" = "udp" ]]
then 
	SOURCE_PORT="0..65535"
fi


if [[ "$DEST_PORT" == "" && "$PROTO" = "tcp" ]]
then 
	DEST_PORT="0..65535"
fi

if [[ "$DEST_PORT" == "" && "$PROTO" = "udp" ]]
then 
	DEST_PORT="0..65535"
fi

}

#Function to validate MAC address

Validate_MacAddress()
{
     
if [[ $1 =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]] 
then
	:
else
	 echo "Invalid MAC Address Entered" 
	 exit $E_INVALIDMAC
fi

}

Validatefilesize()
{
	actualsize=$(wc -c "$1" | cut -d " " -f 1)
	if [[ "$2" == "OPTION1" ]]
	then 	
		if [ $actualsize -ge $minimumsize ] 
		then
			:
		else
			echo ""
    			echo "No packets were filtered, parameters used for filters needs to be checked"
			echo ""
			rm $filename{1,2}
			exit $E_EMPTYPCAP
		fi
	else
		if [ $actualsize -ge $minimumsize ]
		then 
			:
		else
			echo ""
			echo "No packets were filtered, parameters used for filters needs to be checked"
			echo ""
			rm $filename{1,5}
			exit $E_EMPTYPCAP
		fi
	fi
}
case $USER_OPTION in


1)  
# Text inside EOF is multiline echo
cat << EOF

This option is used to replay unidirectional UDP or TCP traffic. 
For example TCP SYN going from ASA inside to outside or DNS request. Enter the MAC address of the ingress interface of the ASA, for example if the ingress interface is
inside you can use the following command to see the MAC address.

ciscoasa# sh interface inside | i MAC
MAC address 0050.568d.c0e2, MTU 1500

Please enter MAC address in same format listed above, four hex digits seprated by dots.

EOF
read ASA_INGRESSMAC
#echo $ASA_INGRESSMAC

ASA_INGRESS_MAC_FORMATTED=$(echo $ASA_INGRESSMAC | sed 's!\.!!g;s!\(..\)!\1:!g;s!:$!!') # This command formats the mac into  six groups of two hexadecimal digits separated by colons (:).
#echo $ASA_INGRESS_MAC_FORMATTED
Validate_MacAddress $ASA_INGRESS_MAC_FORMATTED
userinput OPTION1  # function call to get user input for the flow.

prefix=temp
suffix=$(date +%s)  # The "+%s" option to 'date' is GNU-specific.
filename=$prefix.$suffix.PCAP
#echo "Temporary filename = $filename"
#  It's great for creating "unique and random" temp filenames,

# This command will create a pcap file by filtering the options selected by user.
tshark -r $PCAP -w $filename "($IP_SRC in {$SOURCE_IP} && $IP_DST in {$DEST_IP}) && ($PROTO.$SRC_PORT in {$SOURCE_PORT} && $PROTO.$DST_PORT in {$DEST_PORT})" || exit $E_TSHARK_INVALID
# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.
filename1=option1_$suffix.PCAP
tcprewrite --enet-dmac=$ASA_INGRESS_MAC_FORMATTED --enet-smac=$SOURCE_MAC --infile=$filename --outfile=$filename1 || exit $E_TCPREWRITE_INVALID

# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.
# This if statement block creates a new pcap file after deleting the vlan tag if present

if [ "$VLANID" == "1" ]
        then
		tcprewrite --enet-vlan=del --infile=$filename1 --outfile=$filename1.temp
		mv $filename1.temp $filename1
fi
#size validation 
Validatefilesize $filename1 OPTION1

# To hanldle linux cooked captures
#tcprewrite --dlt=enet -i $filename1 -o $filename2
#mv $filename2 $filename1

# This command is doing the replay, final file name is option_1.pcap
tcpreplay -i $INTERFACE --stats=1 $filename1 || exit $E_TCPREPLAY_INVALID

rm $filename # Cleaning up temporary files
echo ""
echo ""
echo "This will create a file $filename1 in current directory which you can use to replay later with modified options such as packets per second, rate etc "
echo "You can use command like below to view the details of the packet for udp flow, refer to tshark --help for more details"
echo "tshark -r $filename1"
echo "tshark -r $filename1  -T fields -e eth.src -e eth.dst -e ip.src -e ip.dst  -e udp.srcport -e udp.dstport"
echo ""
;;
2)  echo " This option is used to replay bidirectional UDP or TCP traffic. "
# Text inside EOF is multiline echo
cat << EOF
This option is used to replay bidirectional UDP or TCP traffic. 
For example TCP flow going from ASA inside to outside or DNS request/reply. Enter the MAC address of the ingress interface of the ASA, for example if the ingress interface is
inside you can use the following command to see the MAC address.

ciscoasa# sh interface inside | i MAC
MAC address 0050.568d.c0e2, MTU 1500

Please enter MAC address in same format listed above, four hex digits seprated by dots.


EOF
read ASA_INGRESS_MAC_OPTION2
#echo $ASA_INGRESS_MAC_OPTION2
ASA_INGRESS_MAC_FORMATTED_OPTION2=$(echo $ASA_INGRESS_MAC_OPTION2 | sed 's!\.!!g;s!\(..\)!\1:!g;s!:$!!')
#echo $ASA_INGRESS_MAC_FORMATTED_OPTION2
Validate_MacAddress $ASA_INGRESS_MAC_FORMATTED_OPTION2
# Text inside EOF is multiline echo
cat << EOF
Enter the MAC address of the ingress interface of the reply on  ASA, for example if SYN/ACK is seen on dmz interface, enter its MAC address 

ciscoasa# sh interface dmz | i MAC
MAC address 0050.568d.2877, MTU 1500

Please enter MAC address in same format listed above, four hex digits seprated by dots.

EOF

read ASA_EGRESS_MAC_OPTION2
#echo $ASA_EGRESS_MAC_OPTION2


ASA_EGRESS_MAC_FORMATTED_OPTION2=$(echo $ASA_EGRESS_MAC_OPTION2 | sed 's!\.!!g;s!\(..\)!\1:!g;s!:$!!')
#echo $ASA_EGRESS_MAC_FORMATTED_OPTION2

Validate_MacAddress $ASA_EGRESS_MAC_FORMATTED_OPTION2

userinput OPTION2 # function call to get user input for the flow.


prefix=temp
suffix=$(date +%s)  # The "+%s" option to 'date' is GNU-specific.
filename1=$prefix.$suffix.PCAP
#echo "Temporary filename = $filename"
#  It's great for creating "unique and random" temp filenames,

# This command will create a pcap file by filtering the options selected by user.
tshark -r $PCAP -w $filename1 "($IP_SRC in {$SOURCE_IP} && $IP_DST in {$DEST_IP}) && ($PROTO.$SRC_PORT in {$SOURCE_PORT} && $PROTO.$DST_PORT in {$DEST_PORT})" || exit $E_TSHARK_INVALID
# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.
# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.
filename2=option2_$suffix.PCAP
tcprewrite --enet-dmac=$ASA_INGRESS_MAC_FORMATTED_OPTION2 --enet-smac=$SOURCE_MAC --infile=$filename1 --outfile=$filename2 || exit $E_TCPREWRITE_INVALID
# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.

filename3=option2.1_$suffix.PCAP

# This command will create a pcap file by filtering the options selected by user for reverse flow.
tshark -r $PCAP -w $filename3 "($IP_DST in {$SOURCE_IP} && $IP_SRC in {$DEST_IP}) && ($PROTO.$DST_PORT in {$SOURCE_PORT} && $PROTO.$SRC_PORT in {$DEST_PORT})" || exit $E_TSHARK_INVALID
# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.
filename4=option2.2_$suffix.PCAP

# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address for reverse flow.
tcprewrite --enet-dmac=$ASA_EGRESS_MAC_FORMATTED_OPTION2 --enet-smac=$SOURCE_MAC --infile=$filename3 --outfile=$filename4 || exit $E_TCPREWRITE_INVALID
# This command creates a new pcap file with the mac address of the file changed to the ASA ingress interface mac address.

filename5=option2.3_$suffix.PCAP

# This command will create a pcap file by merging two files.
mergecap -w $filename5 $filename4 $filename2 || exit $E_MERGECAP_INVALID

# This if statement block creates a new pcap file after deleting the vlan tag if present
if [ "$VLANID" == "1" ]
        then
		tcprewrite --enet-vlan=del --infile=$filename5 --outfile=option3.pcap || exit $E_TCPREWRITE_INVALID
		mv option3.pcap $filename5
fi

#size validation 
Validatefilesize $filename5

# To handle linux cooked captures
#tcprewrite --dlt=enet -i $filename5 -o $filename6
#mv $filename6 $filename5

# This command is doing the replay. 500 millisecond delay is added within packets as sometimes due to network latency packets timings can lead to unexpected
# results. Example before the syn/ack is seen, third ack in TCP handshake will be seen. Extra delay will not alter results in most cases.
tcpreplay -i $INTERFACE -p 2 --stats=1 $filename5 || exit $E_TCPREPLAY_INVALID
#Cleaning up temporary files.
rm $filename{1,4}
mv $filename5 $filename2
echo ""
echo ""
echo "This will create a file $filename2 2 in current directory which you may  use to replay later with modified options such as packets per second, rate etc "
echo "You can use command like below to view the details of the packet for tcp flow, refer to tshark --help for more details"
echo "tshark -r $filename2"
echo "To view MAC address use options below below"
echo "tshark -r $filename2  -T fields -e eth.src -e eth.dst -e ip.src -e ip.dst  -e tcp.srcport -e tcp.dstport"
echo ""
;;

*)
echo "You selected an invalid option. "
;;

esac	

exit 0

