local months = {
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec",
}

function Pandoc(doc)
	local file_path = PANDOC_STATE.input_files[1]
	local file_basename = file_path:match("([^/]+)$")
	local year, month, day = file_basename:match("^(%d%d%d%d)_(%d%d)_(%d%d)_")
	assert(year and month and day, "Invalid post file_basename: " .. file_basename)

	local time_machine = string.format("%s-%s-%s", year, month, day)
	local time_human = string.format("%s %d, %s", months[tonumber(month)], tonumber(day), year)

	local h1_text = ""
	local blocks_new = pandoc.List()
	local in_section = false

	for _, block in ipairs(doc.blocks) do
		if block.t == "Header" and block.level == 1 then
			h1_text = pandoc.utils.stringify(block.content)
		elseif block.t == "Header" and block.level == 2 then
			--[[ Close previous section ]]
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

	local article_start = string.format(
		[[<article>
            <header>
                <h1>%s</h1>
                <time datetime="%s">%s</time>
            </header>]],
		h1_text,
		time_machine,
		time_human
	)

	blocks_new:insert(1, pandoc.RawBlock("html", article_start))
	blocks_new:insert(pandoc.RawBlock("html", "</article>"))

	return pandoc.Pandoc(blocks_new, doc.meta)
end
