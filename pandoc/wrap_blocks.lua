function CodeBlock(block_code)
	return {
		pandoc.RawBlock("html", "<figure>"),
		block_code,
		pandoc.RawBlock("html", "</figure>"),
	}
end

function BlockQuote(block_quote)
	return {
        pandoc.RawBlock("html", "<figure>"),
        block_quote,
        pandoc.RawBlock("html", "</figure>")
    }
end

function Div(div)
	return div.content
end
