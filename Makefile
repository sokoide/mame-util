TSV ?= m.289.tsv
MERGED ?= 0
FORCE ?= 0
PARALLEL ?= 6
MAME_UTIL_ROM_DIR ?= .
# DL=0: TITLE または FILE で検索 / DL=1: 検索結果のROMをダウンロード
DL ?= 0

# TITLE/FILE をレシピのシェルに渡す（makeの変数展開で $ や ^ が壊れないよう export 経由）
export TITLE FILE

DOWNLOAD_TSV = $(if $(filter 1,$(MERGED)),m.289.merged.tsv,$(TSV))
DOWNLOAD_FORCE = $(if $(filter 1,$(FORCE)),--force,)

# mame.listfull から name を抽出する（DL=0 と DL=1 で共用）
# TITLE が有効な正規表現なら正規表現検索、不正（例: 閉じていない括弧）なら部分一致検索にフォールバック（両方case-insensitive）
SEARCH_SH = rc=0; echo '' | grep -E "$$TITLE" >/dev/null 2>&1 || rc=$$?; \
	if [ $$rc -lt 2 ]; then re=1; else re=0; fi; \
	awk -v re=$$re 'BEGIN { t = tolower(ENVIRON["TITLE"]) } \
	NR > 1 { \
		name = $$1; desc = $$0; \
		sub(/^[^ \t]+[ \t]+/, "", desc); \
		gsub(/^"|"$$/, "", desc); \
		d = tolower(desc); \
		if (re ? d ~ t : index(d, t) > 0) print name ".zip\t" desc \
	}' mame.listfull

# mame.listfull のファイル名列を検索し、ファイル名とタイトル説明を出力する
FILE_SEARCH_SH = rc=0; echo '' | grep -E "$$FILE" >/dev/null 2>&1 || rc=$$?; \
	if [ $$rc -lt 2 ]; then re=1; else re=0; fi; \
	awk -v re=$$re 'BEGIN { t = tolower(ENVIRON["FILE"]) } \
	NR > 1 { \
		name = $$1; file = name ".zip"; desc = $$0; \
		sub(/^[^ \t]+[ \t]+/, "", desc); \
		gsub(/^"|"$$/, "", desc); \
		n = tolower(file); \
		if (re ? n ~ t : index(n, t) > 0) print file "\t" desc \
	}' mame.listfull

.PHONY: default help rsync rsync-no-dryrun merged-tsv listfull

default:
ifeq ($(TITLE)$(FILE),)
	@echo 'usage: DL=0 TITLE="galaxian 3" make   タイトル検索'
	@echo '       DL=0 FILE="harry" make          ファイル名検索'
	@echo '       DL=1 TITLE="xevious" make       タイトル検索してROMをDL'
	@echo '       regex: 有効な拡張正規表現を大小文字無視で使用。メタ文字なしは部分一致と同じ結果'
	@echo '              構文エラーのregex (例: "[hharry") はregexではなく、文字列の部分一致にフォールバック'
endif
ifneq ($(TITLE),)
ifneq ($(FILE),)
	@echo 'TITLEとFILEは同時に指定できません'; exit 1
endif
endif
ifneq ($(DL),0)
ifneq ($(DL),1)
	@echo 'DLは0(検索)か1(ダウンロード)を指定してください'; exit 1
endif
endif
ifneq ($(MERGED),0)
ifneq ($(MERGED),1)
	@echo 'MERGEDは0(通常)か1(merged)を指定してください'; exit 1
endif
endif
ifneq ($(FORCE),0)
ifneq ($(FORCE),1)
	@echo 'FORCEは0(通常)か1(再ダウンロード)を指定してください'; exit 1
endif
endif
ifneq ($(TITLE)$(FILE),)
ifeq ($(DL),0)
ifeq ($(FILE),)
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@printf 'File\tTitle\n'
	@$(SEARCH_SH)
else
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@printf 'File\tTitle\n'
	@$(FILE_SEARCH_SH)
endif
endif
ifeq ($(DL),1)
ifeq ($(FILE),)
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@set -e; \
	results=$$( $(SEARCH_SH) ); \
	test -n "$$results" || { echo '検索結果: 0件'; exit 1; }; \
	printf 'File\tTitle\n%s\n' "$$results"; \
	names=$$(printf '%s\n' "$$results" | cut -f1 | sed 's/\.zip$$//' | tr '\n' ' '); \
	echo "ダウンロード対象: $$names"; \
	python3 download.py -p $(PARALLEL) --tsv $(DOWNLOAD_TSV) --dest $(MAME_UTIL_ROM_DIR) --names $$names $(DOWNLOAD_FORCE)
else
	@test -f mame.listfull || { echo 'mame.listfull がありません。make listfull で生成してください'; exit 1; }
	@test -f $(DOWNLOAD_TSV) || { echo '$(DOWNLOAD_TSV) がありません。make merged-tsv で生成してください'; exit 1; }
	@set -e; \
	results=$$( $(FILE_SEARCH_SH) ); \
	test -n "$$results" || { echo '検索結果: 0件'; exit 1; }; \
	printf 'File\tTitle\n%s\n' "$$results"; \
	names=$$(printf '%s\n' "$$results" | cut -f1 | sed 's/\.zip$$//' | tr '\n' ' '); \
	echo "ダウンロード対象: $$names"; \
	python3 download.py -p $(PARALLEL) --tsv $(DOWNLOAD_TSV) --dest $(MAME_UTIL_ROM_DIR) --names $$names $(DOWNLOAD_FORCE)
endif
endif
endif

help:
	@echo "使い方:"
	@echo '  DL=0 TITLE="galaxian 3" make       mame.listfull をタイトルで検索 (name,"説明")'
	@echo '  DL=0 FILE="harry" make              mame.listfull のROMファイル名を検索 (例: hharry.zip)'
	@echo '  DL=0 TITLE="^foo" make               正規表現でタイトル検索 (case-insensitive, 不正な正規表現は部分一致)'
	@echo '  DL=0 FILE="^hharry.*\.zip$$" make     正規表現でファイル名検索 (同上)'
	@echo '  regexの扱い: TITLE/FILEとも有効な拡張正規表現を大小文字無視で使用'
	@echo '               メタ文字なし (例: "harry") は部分一致と同じ結果。構文エラー (例: "[hharry") は部分一致にフォールバック'
	@echo '  DL=1 TITLE="xevious" make          search の結果のROMをSafariで6並列DL'
	@echo '  DL=1 FILE="harry" make              ファイル名検索の結果をSafariで6並列DL'
	@echo '  DL=1 FILE="nspirit" MERGED=1 make   m.289.merged.tsvのURLからSafariでROMをDL'
	@echo '       TSV生成元URL: https://archive.org/download/mame-roms-merged_/MAME%20ROMs%20(merged)/'
	@echo '  DL=1 FILE="nspirit" FORCE=1 make    保存済みzipも再ダウンロード'
	@echo "  make rsync                         ダウンロード済みzipを外部ドライブへdry-run"
	@echo "  make rsync-no-dryrun               実際にrsyncする"
	@echo "  make listfull                      mame -listfull > mame.listfull を再生成"
	@echo "  make merged-tsv                    m.289.merged.html からTSVを生成"
	@echo "変数: DL=$(DL) (0:検索 1:DL)  MERGED=$(MERGED) (0:通常 1:merged)  FORCE=$(FORCE) (0:既存skip 1:再DL)  TITLE/FILE (同時指定不可)  PARALLEL=$(PARALLEL)  TSV=$(TSV)  MAME_UTIL_ROM_DIR=$(MAME_UTIL_ROM_DIR) (zipの保存先ディレクトリ)"

rsync:
	rsync --dry-run -av --ignore-existing $(MAME_UTIL_ROM_DIR)/*.zip /Volumes/IO512GB/Emu/roms/mame

rsync-no-dryrun:
	rsync -av --ignore-existing $(MAME_UTIL_ROM_DIR)/*.zip /Volumes/IO512GB/Emu/roms/mame

merged-tsv:
	@test -f m.289.merged.html || { echo 'm.289.merged.html がありません'; exit 1; }
	@{ \
		printf 'file name\tURL\tsize\n'; \
		perl -ne 'if (/<td><a href="([^"]+\.zip)">/) { $$file = $$1; $$field = 0 } elsif (defined $$file && /<td>([^<]*)<\/td>/) { $$field++; if ($$field == 2) { printf "%s\thttps://archive.org/download/mame-roms-merged_/MAME%%20ROMs%%20(merged)/%s\t%s\n", $$file, $$file, $$1; undef $$file } }' m.289.merged.html; \
	} > m.289.merged.tsv

listfull:
	mame -listfull > mame.listfull
