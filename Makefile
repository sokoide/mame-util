TSV ?= dl.tsv
PARALLEL ?= 6

.PHONY: download rsync rsync-no-dryryn search listfull

download:
	python3 download.py -p $(PARALLEL) $(TSV)

rsync:
	rsync --dry-run -av --ignore-existing ./*.zip /Volumes/IO512GB/Emu/roms/mame

rsync-no-dryryn:
	rsync -av --ignore-existing ./*.zip /Volumes/IO512GB/Emu/roms/mame

# 使い方: TITLE="galaxian 3" make search
search:
	@test -n "$(TITLE)" || { echo 'usage: TITLE="galaxian 3" make search'; exit 1; }
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@awk -v t="$(TITLE)" 'BEGIN { t = tolower(t) } \
		NR > 1 { \
			name = $$1; desc = $$0; \
			sub(/^[^ \t]+[ \t]+/, "", desc); \
			gsub(/^"|"$$/, "", desc); \
			if (index(tolower(desc), t) > 0) print name ",\"" desc "\"" \
		}' mame.listfull

listfull:
	mame -listfull > mame.listfull
