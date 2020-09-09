VERILOG_ANALYSIS = vlogan -full64 -v2005
ELABORATION      = vcs -full64
TARGET           = simv
SRCS             = simsrc
TOP_MODULE       = top

.PHONY: all run clean

all:
	$(VERILOG_ANALYSIS) -f $(SRCS)
	$(ELABORATION) -o $(TARGET) $(TOP_MODULE)

run:
	./${TARGET}

clean:
	rm -rf $(TARGET) $(TARGET).daidir csrc ucli.key AN.DB
