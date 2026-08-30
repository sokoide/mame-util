TSV ?= m.289.tsv
PARALLEL ?= 6

# mame.listfull から name を抽出するawk（search と download で共用）
SEARCH_AWK = awk -v t="$(1)" 'BEGIN { t = tolower(t) } \
	NR > 1 { \
		name = $$1; desc = $$0; \
		sub(/^[^ \t]+[ \t]+/, "", desc); \
		gsub(/^"|"$$/, "", desc); \
		if (index(tolower(desc), t) > 0) print name ",\"" desc "\"" \
	}' mame.listfull

.PHONY: help download rsync rsync-no-dryrun search listfull

help:
	@echo "使い方:"
	@echo "  make help                          このヘルプを表示"
	@echo '  TITLE="galaxian 3" make search     mame.listfull をタイトルで検索 (name,"説明")'
	@echo '  TITLE="xevious" make download      make search の結果のROMをSafariで6並列DL'
	@echo '  DL="xevious*" make download        m.289.tsv からglob一致するzipをSafariで6並列DL'
	@echo "  make rsync                         ダウンロード済みzipを外部ドライブへdry-run"
	@echo "  make rsync-no-dryrun               実際にrsyncする"
	@echo "  make listfull                      mame -listfull > mame.listfull を再生成"
	@echo "変数: PARALLEL=$(PARALLEL)  TSV=$(TSV)"

download:
ifeq ($(TITLE)$(DL),)
	@echo 'usage: TITLE="xevious" make download  または  DL="xevious*" make download'; exit 1
endif
ifneq ($(TITLE),)
ifneq ($(DL),)
	@echo 'TITLEとDLは同時に指定できません'; exit 1
endif
	@set -e; \
	names=$$( $(call SEARCH_AWK,$(TITLE)) | cut -d, -f1 | tr '\n' ' ' ); \
	test -n "$$names" || { echo '検索結果: 0件'; exit 1; }; \
	echo "検索結果: $$names"; \
	python3 download.py -p $(PARALLEL) --tsv $(TSV) --names $$names
endif
ifneq ($(DL),)
	python3 download.py -p $(PARALLEL) --tsv $(TSV) --pattern '$(DL)'
endif

rsync:
	rsync --dry-run -av --ignore-existing ./*.zip /Volumes/IO512GB/Emu/roms/mame

rsync-no-dryrun:
	rsync -av --ignore-existing ./*.zip /Volumes/IO512GB/Emu/roms/mame

search:
	@test -n "$(TITLE)" || { echo 'usage: TITLE="galaxian 3" make search'; exit 1; }
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@$(call SEARCH_AWK,$(TITLE))

listfull:
	mame -listfull > mame.listfull
