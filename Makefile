TSV ?= dl.tsv
PARALLEL ?= 6

.PHONY: download rsync rsync-no-dryrun

download:
	python3 download.py -p $(PARALLEL) $(TSV)

rsync:
	rsync --dry-run -av --ignore-existing ./*.zip /Volumes/IO512GB/Emu/roms/mame

rsync-no-dryryn:
	rsync -av --ignore-existing ./*.zip /Volumes/IO512GB/Emu/roms/mame
