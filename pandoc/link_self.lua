function Link(link)
	if not link.target:match("^http") then
		link.target = string.sub(link.target, 0, #link.target - 3) --[[ Remove extension ]]
		link.target = string.gsub(link.target, "_", "/", 3)
		link.target = link.target .. ".html"
		link.target = "https://nathanielketema.github.io/" .. link.target
	end
	return link
end
