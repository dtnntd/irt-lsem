# ========================================================================
# IRT-LSEM HNUE Journal manuscript — build orchestrator
# ========================================================================
.PHONY: pdf clean watch count_pages count_words verify

LATEXMK = latexmk -pdf -interaction=nonstopmode -file-line-error -halt-on-error

pdf: main.pdf

main.pdf: main.tex sections/*.tex refs/references.bib style/hnue.sty
	$(LATEXMK) main.tex

watch:
	$(LATEXMK) -pvc main.tex

clean:
	$(LATEXMK) -C
	rm -f *.bbl *.fdb_latexmk *.fls *.synctex.gz *.lof *.lot

count_pages: main.pdf
	@pdfinfo main.pdf | grep -E '^Pages'

count_words: main.pdf
	@echo "Total words (incl. references, captions): $$(pdftotext main.pdf - | wc -w)"

verify: main.pdf
	@echo "=== HNUE compliance smoke-test ==="
	@pdfinfo main.pdf | grep -E '^(Pages|Page size)'
	@echo "--- Sections present ---"
	@pdftotext main.pdf - | grep -cE '^(1\. Giới thiệu|2\. Nội dung nghiên cứu|3\. Kết luận|Tóm tắt|Abstract)' || true
	@echo "--- Repo link in acknowledgements ---"
	@pdftotext main.pdf - | grep -o 'github.com[^[:space:]]*' || echo 'WARNING: no GitHub URL found'
