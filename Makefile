%.html: %.md
	pandoc $< -o $@ --standalone --highlight-style=tango
