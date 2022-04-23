
.PHONY:  help clean  tcpserver1 tcpclient1 tcpserver2 tcpclient2   udpserver1 udpclient1 udpserver2 udpclient2   tcpserverint tcpclientint  udpserverint udpclientint


help:
	-echo	tcpserver1  tcpclient1
	-echo	tcpserver2  tcpclient2
	-echo	udpserver1  udpclient1
	-echo	udpserver2  udpclient2
	-echo	tcpserverint tcpclientint
	-echo	udpserverint udpclientint


clean:
	-rm -f t*.dat


netcat.exe: netcat.lpr unitnet.pas
	fpc netcat.lpr

tcpserver1:netcat.exe
	./netcat.exe -l 5000 >  tsr.dat
	md5sum netcat.exe tsr.dat
tcpclient1:netcat.exe
	./netcat.exe 127.0.0.1 5000 < netcat.exe


tcpserver2:netcat.exe
	./netcat.exe -l 5000 <  netcat.exe
tcpclient2:netcat.exe
	./netcat.exe 127.0.0.1 5000 > tcr.dat
	md5sum tcr.dat netcat.exe



udpserver1:netcat.exe
	./netcat.exe -u -l 5000 >  tusr.dat
	md5sum netcat.exe tusr.dat
udpclient1:netcat.exe
	./netcat.exe -u 127.0.0.1 5000 < netcat.exe



udpserver2:netcat.exe
	./netcat.exe -u -l 5000 <  netcat.exe
udpclient2:netcat.exe
	./netcat.exe -u 127.0.0.1 5000 > tucr.dat
	md5sum tucr.dat netcat.exe



tcpserverint:netcat.exe
	./netcat.exe -l 5000
tcpclientint:netcat.exe
	./netcat.exe 127.0.0.1 5000



udpserverint:netcat.exe
	./netcat.exe -u -l 5000
udpclientint:netcat.exe
	./netcat.exe -u 127.0.0.1 5000

