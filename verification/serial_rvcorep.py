import sys
import serial

port = "/dev/ttyUSB1"

num = 8000000
if len(sys.argv) > 1:
    num = int(sys.argv[1]) * 1000000
num = num if num > 0 else 1000000
name = "test.bin"
if len(sys.argv) > 2:
    name = sys.argv[2]

try:
    with serial.Serial(port, num) as ser:
        print("serial baud rate : "+str(num))
        print("send file : "+name);
        with open(name, mode="rb") as fin:
            content = fin.read()
            ser.write(content)
            while True:
                line = ser.read().decode("ascii")
                print(line, end="", flush=True)
except KeyboardInterrupt:
    print("");
    print("serial program is terminated.")
