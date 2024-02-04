-- this dialog box uses the telescope UI to ask for free text
-- entry, providng the user an option to 

M = {}

-- base class methods caller can override ------------------

M.defaults = {
    title = "Enter an option",
    telescope = require("telescope.themes").get_dropdown({}),
    history_file = "",
    history_group = "DEFAULT",
    history = { DEFAULT = {} },
    last_selection = nil,

    -- callbacks intended for override -------------------------

    item_selected = function(self, txt) -- when user selects an item
        self.last_selection = txt
    end,

    -- callbacks that could be overridden ----------------------

    -- returns contents of history (read file, if history_file is set)
    get_history = function(self)
        return self.history[self.history_group]
    end,

    -- override history (write file, if history_file is set)
    set_history = function(self, items)
        self.history = items
        self:write_history_file()
    end,

    -- return last user selection
    get_selection = function(self)
        return self.last_selection
    end,

    -- add item to history (write file, if history_file is set)
    add_to_history = function(self, txt)
        table.insert(self.history[self.history_group], txt)
        self:write_history_file()
    end,

    -- remove item from hisotry (write file, if history_file is set)
    remove_from_history = function(self, txt)
        for i,v in ipairs(self.history[self.history_group]) do
            if v == txt then
                table.remove(self.history[self.history_group], i)
                self:write_history_file()
                break
            end
        end
    end,

    -- read from history_file to history, if history_file is set
    read_history_file = function(self)
        local file_path = self:get_history_path()
        if file_path == "" then return end

        if vim.fn.filereadable(file_path) == 0 then
            return
        end

        -- deserialize file
        local sandbox_env = {}
        local func,err = loadfile(file_path, "t", sandbox_env)
        if func == nil then
            error(err)
        end

        -- evaluate the result in sandbox
        local obj = nil
        do
            local _env = _ENV
            _ENV = sandbox_env
            obj = func()
            _ENV = _env
        end

        if obj ~= nil then
            self.history = obj
        end
    end,

    -- write from history to history_file, if history_file is set
    write_history_file = function(self)
        local file_path = self:get_history_path(true)
        if file_path == "" then return end

        local tmp = file_path .. "~"

        local file,err1 = io.open(tmp, "w")
        if not file then
            error("failed to open '" .. tmp .. "' for writing: " .. err1)
        end

        file:write("return " .. self:serialize(self.history))
        file:close()

        local ok,err2 = os.rename(tmp, file_path)
        if not ok then
            error("failed to rename '" .. tmp .. "' to '" .. file_path .. "': " .. err2)
        end
    end,

    -- local helpers not intended for replacement --------------

    -- prefixes history_file with ./config/nvim/history
    get_history_path = function(self, create_dir)
        local hfn = self.history_file

        if hfn == nil or hfn == "" then
            return ""
        end
        if hfn[0] == '.' or hfn[0] == '/' then
            return hfn
        end

        local config = vim.fn.stdpath('config')
        local histdir = config .. '/history'

        if vim.fn.isdirectory(histdir) == 0 then
            if not create_dir then return "" end
            local ok,err = vim.fn.mkdir(histdir, "p")
            if not ok then
                error("failed to create directory '" .. histdir .. "': " .. err)
            end
        end

        return histdir .. '/' .. hfn
    end,

    -- convert a lua object into a string
    serialize = function(self, obj)
        if type(obj) == "number" or type(obj) == "boolean" then
            return tostring(obj)
        elseif type(obj) == "string" then
            return string.format('%q', obj)
        elseif type(obj) == "table" then
            local s = "{\n"
            for k, v in pairs(obj) do
                s = s .. "[" .. self:serialize(k) .. "] = " .. self:serialize(v) .. ",\n"
            end
            s = s .. "}"
            return s
        elseif obj == nil then
            return 'nil'
        else
            error("unsupported obj type='" .. obj(type) .. "' obj='" .. vim.inspect(obj) .. "'")
        end
    end,

    -- any entry in obts will override an entry in self
    overwrite_opts = function(self, opts)
        if opts == nil then
            return
        end
        for k,_ in pairs(self) do
            if opts[k] then
                self[k] = opts[k]
            end
        end
    end
}

-- creation of new object ----------------------------------
--
-- nopts can override state and methods of the created
-- object.  intended use case is:
--
-- ```lua
-- local mydialog = require('history-select').new({
--      title = 'Enter an option',
--      history_file = 'my-database'
--      item_selected = function(selected)
--          print(selected)
--      end
-- })
-- mydialog:ask({ history_group = 'first' })
-- mydialog:ask({ history_group = 'second' })
-- ```
--
-- each time the same dialog is invoked, the user selected
-- which history group will be recalled/updated.

M.new = function(nopts)
    local obj = vim.deepcopy(M.defaults) -- create a new instance
    obj:overwrite_opts(nopts) -- override with nopts entries from caller

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf_val = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    obj.ask = function(self, iopts)
        self:overwrite_opts(iopts) -- another opportunity for the caller to override

        pickers.new(self.telescope, {
            prompt_title = self.title,
            finder = finders.new_table({
                results = self:get_history(),
            }),
            sorter = conf_val.generic_sorter(self.telescope),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()

                    if selection ~= nil then
                        self:item_selected(selection[1])
                        return
                    end

                    self:add_to_history(action_state.get_current_line())
                end)

                map("i", "<c-e>", function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    self:add_to_history(selection[1])
                end)

                map("i", "<c-d>", function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    self:remove_from_history(selection[1])
                end)
                return true
            end,
        }):find()
    end

    obj:read_history_file()

    return obj
end

return M
