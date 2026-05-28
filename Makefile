%.html: %.md
	pandoc $< -o $@ --template=template.html --highlight-style=tango --css=../../css/style.css
