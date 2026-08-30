TSV ?= m.289.tsv
PARALLEL ?= 6
MAME_UTIL_ROM_DIR ?= .

# TITLE をレシピのシェルに渡す（makeの変数展開で $ や ^ が壊れないよう export 経由）
export TITLE

# mame.listfull から name を抽出するawk（search と download で共用）
# TITLE に正規表現メタ文字（.$^*+?[](){}|\）があれば正規表現検索、なければ部分一致検索（両方case-insensitive）
SEARCH_AWK = awk -v t="$$TITLE" 'BEGIN { \
	t = tolower(t); \
	meta = ".$$^*+?[](){}|\\"; \
	re = 0; \
	for (i = 1; i <= length(meta); i++) { \
		if (index(t, substr(meta, i, 1)) > 0) { re = 1; break } \
	} \
} \
	NR > 1 { \
		name = $$1; desc = $$0; \
		sub(/^[^ \t]+[ \t]+/, "", desc); \
		gsub(/^"|"$$/, "", desc); \
		d = tolower(desc); \
		if (re ? d ~ t : index(d, t) > 0) print name ",\"" desc "\"" \
	}' mame.listfull

.PHONY: help download rsync rsync-no-dryrun search listfull

help:
	@echo "使い方:"
	@echo "  make help                          このヘルプを表示"
	@echo '  TITLE="galaxian 3" make search     mame.listfull をタイトルで検索 (name,"説明")'
	@echo '  TITLE="^foo" make search           正規表現で検索 (case-insensitive, メタ文字使用時)'
	@echo '  TITLE="xevious" make download      make search の結果のROMをSafariで6並列DL'
	@echo '  DL="xevious*" make download        m.289.tsv からglob一致するzipをSafariで6並列DL'
	@echo "  make rsync                         ダウンロード済みzipを外部ドライブへdry-run"
	@echo "  make rsync-no-dryrun               実際にrsyncする"
	@echo "  make listfull                      mame -listfull > mame.listfull を再生成"
	@echo "変数: PARALLEL=$(PARALLEL)  TSV=$(TSV)  MAME_UTIL_ROM_DIR=$(MAME_UTIL_ROM_DIR) (zipの保存先ディレクトリ)"

download:
ifeq ($(TITLE)$(DL),)
	@echo 'usage: TITLE="xevious" make download  または  DL="xevious*" make download'; exit 1
endif
ifneq ($(TITLE),)
ifneq ($(DL),)
	@echo 'TITLEとDLは同時に指定できません'; exit 1
endif
	@set -e; \
	names=$$( $(SEARCH_AWK) | cut -d, -f1 | tr '\n' ' ' ); \
	test -n "$$names" || { echo '検索結果: 0件'; exit 1; }; \
	echo "検索結果: $$names"; \
	python3 download.py -p $(PARALLEL) --tsv $(TSV) --dest $(MAME_UTIL_ROM_DIR) --names $$names
endif
ifneq ($(DL),)
	python3 download.py -p $(PARALLEL) --tsv $(TSV) --dest $(MAME_UTIL_ROM_DIR) --pattern '$(DL)'
endif

rsync:
	rsync --dry-run -av --ignore-existing $(MAME_UTIL_ROM_DIR)/*.zip /Volumes/IO512GB/Emu/roms/mame

rsync-no-dryrun:
	rsync -av --ignore-existing $(MAME_UTIL_ROM_DIR)/*.zip /Volumes/IO512GB/Emu/roms/mame

search:
	@test -n "$(TITLE)" || { echo 'usage: TITLE="galaxian 3" make search'; exit 1; }
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@$(SEARCH_AWK)

listfull:
	mame -listfull > mame.listfull
