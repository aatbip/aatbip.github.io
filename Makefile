%.html: %.md
	pandoc $< -o $@ --standalone --highlight-style=tango --css=../../css/style.css
