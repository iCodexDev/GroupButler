local config = require "groupbutler.config"
local locale = require "groupbutler.languages"
local i18n = locale.translate
local null = require "groupbutler.null"
local api_err = require "groupbutler.api_errors"

local _M = {}

function _M:new(update_obj)
	local plugin_obj = {}
	setmetatable(plugin_obj, {__index = self})
	for k, v in pairs(update_obj) do
		plugin_obj[k] = v
	end
	return plugin_obj
end

local function get_reply_markup(self, msg, text)
	local reply_markup, new_text = self.u:reply_markup_from_text(text)
	return reply_markup, new_text:replaceholders(msg, "rules", "title")
end

local function pin_message(self, chat_id, message_id)
	self.red:set("chat:"..chat_id..":pin", message_id)
	return self.api:pin_chat_message(chat_id, message_id, self.u:is_silentmode_on(chat_id))
end

local function new_pin(self, msg, pin_text)
	local reply_markup, text = get_reply_markup(self, msg, pin_text)
	local ok, err = self.api:send_message{
		chat_id = msg.chat.id,
		text = text,
		parse_mode = "Markdown",
		disable_web_page_preview = true,
		reply_markup = reply_markup
	}

	if not ok then
		msg:send_reply(api_err.trans(err), "Markdown")
		return
	end

	pin_message(self, msg.chat.id, ok.message_id)
	return
end

local function edit_pin(self, msg, pin_text)
	local pin_id = self.red:get("chat:"..msg.chat.id..":pin")
	if pin_id == null then
		new_pin(self, msg, pin_text)
		return
	end
	local reply_markup, text = get_reply_markup(self, msg, pin_text)
	local ok, err = self.api:edit_message_text{
		chat_id = msg.chat.id,
		message_id = pin_id,
		text = text,
		parse_mode = "Markdown",
		disable_web_page_preview = true,
		reply_markup = reply_markup
	}
	if not ok then
		if err.description:lower():match("message to edit not found") then
			new_pin(self, msg, pin_text)
			return
		end
		msg:send_reply(api_err.trans(err), "Markdown")
		return
	end
	pin_message(self, msg.chat.id, ok.message_id)
	return
end

local function last_pin(self, msg)
	local pin_id = self.red:get("chat:"..msg.chat.id..":pin")
	if pin_id == null then
		msg:send_reply(i18n("I couldn't find any message generated by <code>/pin</code>."), "html")
		return
	end
	local ok, err = self.api:send_message{
		chat_id = msg.chat.id,
		text = i18n("Last message generated by <code>/pin</code> ^"),
		parse_mode = "html",
		reply_to_message_id = pin_id,
	}
	if not ok and err.description:lower():match("reply message not found") then
		msg:send_reply(i18n("The old message generated with <code>/pin</code> does not exist anymore."), "html")
		self.red:del("chat:"..msg.chat.id..":pin")
		return
	end
end

function _M:onTextMessage(blocks)
	local msg = self.message

	if msg.chat.type == "private"
	or not msg:is_from_admin() then
		return
	end

	local pin_text = blocks[2]
	if msg.reply_to_message and msg.reply_to_message.text then
		pin_text = msg.reply_to_message.text
	end

	if not pin_text then
		last_pin(self, msg)
		return
	end

	if blocks[1] == "newpin" then
		new_pin(self, msg, pin_text)
		return
	end

	edit_pin(self, msg, pin_text)
	return
end

_M.triggers = {
	onTextMessage = {
		config.cmd..'(pin)$',
		config.cmd..'(pin) (.*)$',
		config.cmd..'(newpin) (.*)$'
	}
}

return _M
