# Introduction
This document describes TCP Replay to replay network traffic from PCAP files. Two approaches will be demonstrated, one manual and other using a bash script.  
Goal is to share this setup idea which can make the repro of issues which needs replay to be quicker. Normally TAC engineers will have some linux VM and firewall setup   
in lab. For this to work two interfaces on ASA e.g inside and dmz will need to be in same VLAN as VM NIC.  

# Topology

+-----------------+
      |      ASA        |
      |  +---------+    |
      |  |  DMZ    |----|--\
      |  +---------+    |   \
      |  +---------+    |    [VLAN]
      |  | INSIDE  |----|   /
      |  +---------+    |  /
      +-----------------+
                         \
                          \
                           \   
                            +------+
                            | Linux |
                            |  VM   |
                            +------+
# Requisites

Linux VM with one NIC.  
FTD or ASA.  
ASA/FTD ingress and egress intterfaces and VM NIC needs to be in same VLAN.  

# Manual Setup

***Case 1, Replay Unidirectional TCP or UDP Traffic.***  

**1.** Create a CAPO file which has only the unidirectional flow. You can filter the packets and then export specified packets to create a file.  

**2.** Rewrite the source and destination MAC address in CAPE file using tcprewrite, see example    
    tcprewrite --enet-dmac=00:55:22:AF:C6:37 --enet-smac=00:44:66:FC:29:AF --infile=input.PCAP --outfile=output.PCAP   
   
    "--enet-smac=00:55:22:AF:C6:37" will be the ASA/FTD interface MAC address and "--enet-smac=00:44:66:FC:29:AF" will be VM NIC MAC address.  
   
    refer:  
    https://tcpreplay.appneta.com/wiki/tcprewrite#rewriting-source-&-destination-mac-addresses  

**3.** Replay the modified PCAP file, see example below, where ens192 is the NIC on VM and output.PCAP is file that needs to be replayed.  
    tcpreplay -i ens192 output.PCAP  

***Case 2, Replay Bidirectional TCP or UDP Traffic.***  

**1.** Create two PCAP files which will contain unidirectional flows i.e if you need to replay Telnet PCAP, one file will contain flow going from client to server and   
    other will contain from server to client.  

**2.** Rewrite the source and destination mac address for each file see example  
    tcprewrite --enet-dmac=00:55:22:AF:C6:37 --enet-smac=00:44:66:FC:29:AF --infile=input.PCAP --outfile=output.PCAP  
  
    "--enet-dmac=00:55:22:AF:C6:37" is the ASA ingress interface MAC for this side of flow. if TCP SYN goes from inside to outside in PCAP, MAC address will be inside  
    interface MAC.  
   
    Similarly do the same for other side of flow.  
    tcprewrite --enet-dmac=00:55:22:AF:C6:37 --enet-smac=00:44:66:FC:29:AF --infile=input1.PCAP --outfile=output1.PCAP  
  
    "--enet-dmac=00:55:22:AF:C6:37" will be the MAC address of the ASA DMZ interface if the SYN/ACK comes on DMZ.  
    Source mac on both statements will be VM NIC.  

**3.** Merge the two PCAP files using wireshark. Open one file i.e output.PCAP in example above and click on "file" then merge and select the output1.file. Save this  
    merged file it will be the file used for replay. 

**4.** Replay the merged PCAP file, see example below, where ens192 is the NIC on VM and merge.PCAP is file that needs to be replayed.   
    tcpreplay -i ens192 merge.PCAP  

# ASA/FTD configuration  
On ASA/FTD you will need to configure required ACL, routes and ARP entries. Please see example below:  
SYN is coming on inside interface and egress interface is dmz, SYN/ACK comes on dmz interface.  
Captures on ASA inside  
ciscoasa# sh capture capi  


   1: 18:16:39.646557       192.168.0.2.1550 > 192.168.0.1.23: S 2579865836:2579865836(0) win 32120 <mss 1460,sackOK,timestamp 10233636 0,nop,wscale 0>   
   2: 18:16:40.646923       192.168.0.1.23 > 192.168.0.2.1550: S 401695549:401695549(0) ack 2579865837 win 17376 <mss 1380,nop,wscale 0,nop,nop,timestamp 2467372 10233636>   
   3: 18:16:41.646817       192.168.0.2.1550 > 192.168.0.1.23: . ack 401695550 win 32120 <nop,nop,timestamp 10233636 2467372>   

Captures on ASA dmz

ciscoasa# sh capture capo  


   1: 18:16:39.646878       192.168.0.2.1550 > 192.168.0.1.23: S 2579865836:2579865836(0) win 32120 <mss 1380,sackOK,timestamp 10233636 0,nop,wscale 0>   
   2: 18:16:40.646817       192.168.0.1.23 > 192.168.0.2.1550: S 401695549:401695549(0) ack 2579865837 win 17376 <mss 1448,nop,wscale 0,nop,nop,timestamp 2467372 10233636>   
   3: 18:16:41.646908       192.168.0.2.1550 > 192.168.0.1.23: . ack 401695550 win 32120 <nop,nop,timestamp 10233636 2467372>   

Routes  
ciscoasa# sh route 192.168.0.2  

Routing entry for 192.168.0.2 255.255.255.255  
  Known via "static", distance 1, metric 0  
  Routing Descriptor Blocks:  
  * 192.168.1.108, via inside  
      Route metric is 0, traffic share count is 1  

ciscoasa# sh route 192.168.0.1  

Routing entry for 192.168.0.1 255.255.255.255  
  Known via "static", distance 1, metric 0  
  Routing Descriptor Blocks:  
  * 172.16.1.10, via dmz  
      Route metric is 0, traffic share count is 1  

route dmz 192.168.0.1 255.255.255.255 172.16.1.10 1   
route inside 192.168.0.2 255.255.255.255 192.168.1.108 1   

Normally these next hop address will be dummy/non-existent, you will need to add static ARP entry as well.     

Something like below:

arp inside 192.168.1.108 0050.568d.c0e2 
arp dmz 172.16.1.10 0050.568d.2877 


***Potential Gotchas***

Sometimes in virtual enviornments, if arp like aaaa.bbbb.cccc is added, it might cause some packet loops as switches will broadcast unknown unicast addresses. To get    
around the issue, you can add MAC of the ASA interfaces in these entries.    

ciscoasa# sh interface inside | i MAC
	MAC address 0050.568d.c0e2, MTU 1500
ciscoasa# sh interface dmz | i MAC   
	MAC address 0050.568d.2877, MTU 1500

On the inside interface arp entry you can use same MAC address of inside.  

One more issue observed is sometimes there will be will packet input on dmz interface if this interface is otherwise not used i.e you will only see packets on inside     
interface and nothing input on dmz. To get around the issue you can ping any arbitraty IP address on dmz subnet    

ciscoasa# sh ip | i dmz
GigabitEthernet0/0       dmz                    172.16.1.1      255.255.255.0   CONFIG
GigabitEthernet0/0       dmz                    172.16.1.1      255.255.255.0   CONFIG
ciscoasa# ping 172.16.1.99
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 172.16.1.99, timeout is 2 seconds:
???

You can choose any IP address to ping and it should solve the issue.  

***End of Gotchas***

For the TCP bidirectional flow, sequence number randomization needs to be disabled.  

example

class-map tcp_bypass
 match access-list tcp_bypass

ciscoasa# sh access-list tcp_bypass
access-list tcp_bypass line 3 extended permit tcp any any eq telnet (hitcnt=873) 0x589e61b3 


policy-map global_policy
class tcp_bypass
  set connection random-sequence-number disable

# Automated replay using bash script

Goal of the script is to act as a wrapper to hide the syntax and eliminate the need to open GUI to make the test faster.  
Options used in script are verbose enough to guide the user to walk through the steps.  


***Use Case 1, Automated Replay for Unidirectional TCP or UDP Traffic***

root@rajat-virtual-machine:/home/rajat/myscripts# ./asareplay.sh 

To run this script following programs needs to be installed

tcpreplay
tcprewrite
tshark
mergecap

tcpreplay and tcprewrite are part of tcpreplay distribution.
tshark and mergecap part of the Wireshark distribution.
If you do not have these installed, press CTRL+C and install these first.

Press any key to continue

To Replay Unidirectional UDP or TCP Traffic Press 1. 
To Replay Bidirectional UDP or TCP Traffic Press 2. 
1

This option is used to replay unidirectional UDP or TCP traffic. 
For example TCP SYN going from ASA inside to outside or DNS request. Enter the MAC address of the ingress interface of the ASA, for example if the ingress interface is
inside you can use the following command to see the MAC address.

ciscoasa# sh interface inside | i MAC
MAC address 0050.568d.c0e2, MTU 1500

Please enter MAC address in same format listed above, four hex digits seprated by dots.

0050.568d.c0e2
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
lo : 127.0.0.1
lo : ::1
ens192 : 192.168.1.38
ens192 : fe80::9277:842e:d663:1481
ens32 : 172.16.1.10
ens32 : fe80::8ce6:490:f5aa:9d6

ens192

Enter the name of the pcap file
/home/rajat/dns.pcap

Please enter minimum one option from Source IP, Destination IP, Source Port, Destination Port.

Enter the Source IP address or subnet in CIDR notation of the flow that needs to be replayed. See examples below
Single host enter 10.1.1.1, subnet enter 10.1.1.0/24, two subnets enter CIDR separated by a space 10.1.1.0/24 192.168.1.0/24.
If you do not want to filter by Source IP address leave it blank and press enter.
HINT: To see the packet details on CLI, use the command 'tshark -r file.pcap', where file.pcap is capture file name



Enter the Destination IP address or subnet in CIDR notation of the flow that needs to be replayed. See examples below.
Single host enter 10.1.1.1, subnet enter 10.1.1.0/24, two subnets enter CIDR separated by a space 10.1.1.0/24 192.168.1.0/24.
If you do not want to filter by Destination IP address leave it blank and press enter.



Enter the transport layer protocol valid option for this script are TCP and UDP 

udp

Enter the source port number of the flow that needs to be replayed, e.g if the protocol is TCP, any valid wireshark filter for tcp.src can be used.
If you do not want to filter by Source port or if the protocol is ICMP leave it blank and press enter.



Enter the Destination port number of the flow that needs to be replayed, e.g if the protocol is TCP, any valid wireshark filter for tcp.dst can be used.
If you do not want to filter by destination port leave it blank and press enter.

53

If VLAN ID needs to be deleted or of traces do not contain VLAN ID enter 1
If VLAN ID needs to be preserved enter 2   

1  

Running as user "root" and group "root". This could be dangerous.  
Test start: 2024-12-29 23:35:48.231185 ...   
Test complete: 2024-12-29 23:35:48.231520   
Actual: 2 packets (142 bytes) sent in 0.000335 seconds   
Rated: 423880.5 Bps, 3.39 Mbps, 5970.14 pps  
Statistics for network device: ens192  
	Successful packets:        2  
	Failed packets:            0  
	Truncated packets:         0  
	Retried packets (ENOBUFS): 0  
	Retried packets (EAGAIN):  0  


This will create a file option1_1735511747.PCAP in current directory which you can use to replay later with modified options such as packets per second, rate etc   

You can use command like below to view the details of the packet for udp flow, refer to tshark --help for more details  

tshark -r option1_1735511747.PCAP  -T fields -e eth.src -e eth.dst -e ip.src -e ip.dst  -e udp.srcport -e udp.dstport  

root@rajat-virtual-machine:/home/rajat/myscripts# tshark -r option1_1735511747.PCAP  

Running as user "root" and group "root". This could be dangerous.  
    1   0.000000 192.168.1.38 → 144.254.71.184 DNS 71 Standard query 0x4bad A alibaba.com  
    2   0.000134 192.168.1.38 → 144.254.71.184 DNS 71 Standard query 0x43d3 AAAA alibaba.com  

root@rajat-virtual-machine:/home/rajat/myscripts# tshark -r option1_1735511747.PCAP  -T fields -e eth.src -e eth.dst -e ip.src -e ip.dst  -e udp.srcport -e udp.dstport  

Running as user "root" and group "root". This could be dangerous.  
00:50:56:8d:99:2b	00:50:56:8d:c0:e2	192.168.1.38	144.254.71.184	44051	53  
00:50:56:8d:99:2b	00:50:56:8d:c0:e2	192.168.1.38	144.254.71.184	33883	53  

root@rajat-virtual-machine:/home/rajat/myscripts# tcpreplay -i ens192 option1_1735511747.PCAP   
Actual: 2 packets (142 bytes) sent in 0.000180 seconds  
Rated: 788888.8 Bps, 6.31 Mbps, 11111.11 pps  
Statistics for network device: ens192  
	Successful packets:        2  
	Failed packets:            0  
	Truncated packets:         0  
	Retried packets (ENOBUFS): 0  
	Retried packets (EAGAIN):  0  


***Use Case 2, Automated Replay for Bidirectional TCP or UDP Traffic***


root@rajat-virtual-machine:/home/rajat/myscripts# ./asareplay.sh 
To run this script following programs needs to be installed

tcpreplay
tcprewrite
tshark
mergecap

tcpreplay and tcprewrite are part of tcpreplay distribution.
tshark and mergecap part of the Wireshark distribution.
If you do not have these installed, press CTRL+C and install these first.

Press any key to continue

To Replay Unidirectional UDP or TCP Traffic Press 1. 
To Replay Bidirectional UDP or TCP Traffic Press 2. 
2
 This option is used to replay bidirectional UDP or TCP traffic. 
This option is used to replay bidirectional UDP or TCP traffic. 
For example TCP flow going from ASA inside to outside or DNS request/reply. Enter the MAC address of the ingress interface of the ASA, for example if the ingress interface is
inside you can use the following command to see the MAC address.

ciscoasa# sh interface inside | i MAC
MAC address 0050.568d.c0e2, MTU 1500

Please enter MAC address in same format listed above, four hex digits seprated by dots.


0050.568d.c0e2
Enter the MAC address of the ingress interface of the reply on  ASA, for example if SYN/ACK is seen on dmz interface, enter its MAC address 

ciscoasa# sh interface dmz | i MAC
MAC address 0050.568d.2877, MTU 1500

Please enter MAC address in same format listed above, four hex digits seprated by dots.

0050.568d.2877
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
lo : 127.0.0.1
lo : ::1
ens192 : 192.168.1.38
ens192 : fe80::9277:842e:d663:1481
ens32 : 172.16.1.10
ens32 : fe80::8ce6:490:f5aa:9d6

ens192

Enter the name of the pcap file
telnetsample.pcap

Please enter minimum one option from Source IP, Destination IP, Source Port, Destination Port.

Enter the Source IP address or subnet in CIDR notation of the flow that needs to be replayed. See examples below
Single host enter 10.1.1.1, subnet enter 10.1.1.0/24, two subnets enter CIDR separated by a space 10.1.1.0/24 192.168.1.0/24.
If you do not want to filter by Source IP address leave it blank and press enter.
HINT: To see the packet details on CLI, use the command 'tshark -r file.pcap', where file.pcap is capture file name



Enter the Destination IP address or subnet in CIDR notation of the flow that needs to be replayed. See examples below.
Single host enter 10.1.1.1, subnet enter 10.1.1.0/24, two subnets enter CIDR separated by a space 10.1.1.0/24 192.168.1.0/24.
If you do not want to filter by Destination IP address leave it blank and press enter.



Enter the transport layer protocol valid option for this script are TCP and UDP 

tcp

Enter the source port number of the flow that needs to be replayed, e.g if the protocol is TCP, any valid wireshark filter for tcp.src can be used.
If you do not want to filter by Source port or if the protocol is ICMP leave it blank and press enter.



Enter the Destination port number of the flow that needs to be replayed, e.g if the protocol is TCP, any valid wireshark filter for tcp.dst can be used.
If you do not want to filter by destination port leave it blank and press enter.

23

If VLAN ID needs to be deleted or of traces do not contain VLAN ID enter 1
If VLAN ID needs to be preserved enter 2

1
Running as user "root" and group "root". This could be dangerous.  
Running as user "root" and group "root". This could be dangerous.  
Test start: 2024-12-29 23:51:16.335137 ...   
Actual: 3 packets (214 bytes) sent in 1.00 seconds   
Rated: 213.9 Bps, 0.001 Mbps, 2.99 pps   
Actual: 5 packets (376 bytes) sent in 2.00 seconds  
Rated: 187.9 Bps, 0.001 Mbps, 2.49 pps   
Actual: 8 packets (577 bytes) sent in 3.50 seconds  
Rated: 164.8 Bps, 0.001 Mbps, 2.28 pps  
Actual: 11 packets (864 bytes) sent in 5.00 seconds  
Rated: 172.7 Bps, 0.001 Mbps, 2.19 pps  
Actual: 13 packets (1023 bytes) sent in 6.00 seconds  
Rated: 170.4 Bps, 0.001 Mbps, 2.16 pps   
Actual: 16 packets (1245 bytes) sent in 7.50 seconds   
Rated: 170.7 Bps, 0.001 Mbps, 2.02 pps  
***more lines***  
Test complete: 2024-12-29 23:52:01.835274  
Actual: 92 packets (7748 bytes) sent in 45.50 seconds  
Rated: 170.2 Bps, 0.001 Mbps, 2.02 pps  
Statistics for network device: ens192  
	Successful packets:        92  
	Failed packets:            0  
	Truncated packets:         0  
	Retried packets (ENOBUFS): 0  
	Retried packets (EAGAIN):  0  


This will create a file option2_1735512675.PCAP 2 in current directory which you may  use to replay later with modified options such as packets per second, rate etc   
You can use command like below to view the details of the packet for tcp flow, refer to tshark --help for more details  

tshark -r option2_1735512675.PCAP  

To view MAC address use options below below  

tshark -r option2_1735512675.PCAP  -T fields -e eth.src -e eth.dst -e ip.src -e ip.dst  -e tcp.srcport -e tcp.dstport  

root@rajat-virtual-machine:/home/rajat/myscripts# tshark -r option2_1735512675.PCAP  
Running as user "root" and group "root". This could be dangerous.  
    1   0.000000  192.168.0.2 → 192.168.0.1  TCP 74 1550 → 23 [SYN] Seq=2579865836 Win=32120 Len=0 MSS=1460 SACK_PERM=1 TSval=10233636 TSecr=0 WS=1  
    2   0.002525  192.168.0.1 → 192.168.0.2  TCP 74 23 → 1550 [SYN, ACK] Seq=401695549 Ack=2579865837 Win=17376 Len=0 MSS=1448 WS=1 TSval=2467372 TSecr=10233636  
    3   0.002572  192.168.0.2 → 192.168.0.1  TCP 66 1550 → 23 [ACK] Seq=2579865837 Ack=401695550 Win=32120 Len=0 TSval=10233636 TSecr=2467372  
    4   0.004160  192.168.0.2 → 192.168.0.1  TELNET 93 Telnet Data ...  
    5   0.150335  192.168.0.1 → 192.168.0.2  TELNET 69 Telnet Data ...   
    6   0.150402  192.168.0.2 → 192.168.0.1  TCP 66 1550 → 23 [ACK] Seq=2579865864 Ack=401695553 Win=32120 Len=0 TSval=10233651 TSecr=2467372  
    ***more lines***  
   92  39.571274  192.168.0.1 → 192.168.0.2  TCP 66 23 → 1550 [ACK] Seq=401696922 Ack=2579866101 Win=17375 Len=0 TSval=2467451 TSecr=10237593
root@rajat-virtual-machine:/home/rajat/myscripts# tshark -r option2_1735512675.PCAP  -T fields -e eth.src -e eth.dst -e ip.src -e ip.dst  -e tcp.srcport -e tcp.dstport
Running as user "root" and group "root". This could be dangerous.
    00:50:56:8d:99:2b	00:50:56:8d:c0:e2	192.168.0.2	192.168.0.1	1550	23  
    00:50:56:8d:99:2b	00:50:56:8d:28:77	192.168.0.1	192.168.0.2	23	155  
    00:50:56:8d:99:2b	00:50:56:8d:c0:e2	192.168.0.2	192.168.0.1	1550	23  
    00:50:56:8d:99:2b	00:50:56:8d:c0:e2	192.168.0.2	192.168.0.1	1550	23  
    ***more lines***     

    00:50:56:8d:99:2b	00:50:56:8d:28:77	192.168.0.1	192.168.0.2	23	1550  


Packets seen on ASA


ciscoasa#  sh capture capi

87 packets captured

   1: 22:54:29.219471       192.168.0.2.1550 > 192.168.0.1.23: S 2579865836:2579865836(0) win 32120 <mss 1460,sackOK,timestamp 10233636 0,nop,wscale 0>   
   2: 22:54:29.719765       192.168.0.1.23 > 192.168.0.2.1550: S 401695549:401695549(0) ack 2579865837 win 17376 <mss 1380,nop,wscale 0,nop,nop,timestamp 2467372 10233636>   
   3: 22:54:30.219440       192.168.0.2.1550 > 192.168.0.1.23: . ack 401695550 win 32120 <nop,nop,timestamp 10233636 2467372>   
   4: 22:54:30.719552       192.168.0.2.1550 > 192.168.0.1.23: P 2579865837:2579865864(27) ack 401695550 win 32120 <nop,nop,timestamp 10233636 2467372>   
   5: 22:54:31.219822       192.168.0.1.23 > 192.168.0.2.1550: P 401695550:401695553(3) ack 2579865864 win 17349 <nop,nop,timestamp 2467372 10233636>   
   ***more lines***    
  87: 22:55:14.719277       192.168.0.1.23 > 192.168.0.2.1550: . ack 2579866101 win 17375 <nop,nop,timestamp 2467451 10237593>   
87 packets shown  
ciscoasa#    sh cap  
ciscoasa#    sh capture capo   

87 packets captured

   1: 22:54:29.219760       192.168.0.2.1550 > 192.168.0.1.23: S 2579865836:2579865836(0) win 32120 <mss 1380,sackOK,timestamp 10233636 0,nop,wscale 0>   
   2: 22:54:29.719658       192.168.0.1.23 > 192.168.0.2.1550: S 401695549:401695549(0) ack 2579865837 win 17376 <mss 1448,nop,wscale 0,nop,nop,timestamp 2467372 10233636>   
   3: 22:54:30.219532       192.168.0.2.1550 > 192.168.0.1.23: . ack 401695550 win 32120 <nop,nop,timestamp 10233636 2467372>    
   4: 22:54:30.719643       192.168.0.2.1550 > 192.168.0.1.23: P 2579865837:2579865864(27) ack 401695550 win 32120 <nop,nop,timestamp 10233636 2467372>   
   5: 22:54:31.219745       192.168.0.1.23 > 192.168.0.2.1550: P 401695550:401695553(3) ack 2579865864 win 17349 <nop,nop,timestamp 2467372 10233636>     
   6: 22:54:31.719613       192.168.0.2.1550 > 192.168.0.1.23: . ack 401695553 win 32120 <nop,nop,timestamp 10233651 2467372>     
   7: 22:54:32.219547       192.168.0.2.1550 > 192.168.0.1.23: P 2579865864:2579865867(3) ack 401695553 win 32120 <nop,nop,timestamp 10233651 2467372>   
   ***more lines***       
  87: 22:55:14.719201       192.168.0.1.23 > 192.168.0.2.1550: . ack 2579866101 win 17375 <nop,nop,timestamp 2467451 10237593>   
87 packets shown
ciscoasa#     sh cap
ciscoasa#     sh capture asp | i 192.168.0.1



# ASA/FTD configuration for automated version

It will be same as discussed above. No changes.



***Notice***      

This command is doing the replay for the bidirection case. 500 millisecond delay is added within packets as sometimes due to network latency packets timings    
can lead to unexpected results. Example before the syn/ack is seen, third ack in TCP handshake will be seen. Extra delay will not alter results in most cases.    

tcpreplay -i $INTERFACE -p 2 --stats=1 $filename5  

 


