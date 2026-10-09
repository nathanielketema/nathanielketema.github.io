function Pandoc(doc)
	local h1_text = ""
	local blocks_new = pandoc.List()
	local in_section = false

	for _, block in ipairs(doc.blocks) do
		if block.t == "Header" and block.level == 1 then
			h1_text = pandoc.utils.stringify(block.content)
			local header_start = string.format(
				[[<section>
                <header>
                    <h1>%s</h1>
                </header>]],
				h1_text
			)
			blocks_new:insert(pandoc.RawBlock("html", header_start))
            in_section = true
		elseif block.t == "Header" and block.level == 2 then
			-- Close previous section
			if in_section then
				blocks_new:insert(pandoc.RawBlock("html", "</section>"))
			end

			local h2_text = pandoc.utils.stringify(block.content)
			local h2_id = h2_text:gsub("[^%w%s-]", ""):gsub("%s+", "-")

			local header_html = string.format(
				[[<section id="%s">
                    <h2><a href="#%s">%s</a></h2>]],
				h2_id,
				h2_id,
				h2_text
			)

			blocks_new:insert(pandoc.RawBlock("html", header_html))
			in_section = true
		else
			blocks_new:insert(block)
		end
	end

	if in_section then
		blocks_new:insert(pandoc.RawBlock("html", "</section>"))
	end

	return pandoc.Pandoc(blocks_new, doc.meta)
end
