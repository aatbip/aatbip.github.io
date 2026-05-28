MD_FILES := $(shell find notes -name "*.md")
HTML_FILES := $(MD_FILES:.md=.html)

all: $(HTML_FILES)

%.html: %.md
	pandoc $< -o $@ --template=template.html --highlight-style=tango --css=../../css/style.css
