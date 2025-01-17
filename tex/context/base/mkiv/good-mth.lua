if not modules then modules = { } end modules ['good-mth'] = {
    version   = 1.000,
    comment   = "companion to font-lib.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local type, next, tonumber, unpack = type, next, tonumber, unpack
local ceil = math.ceil
local match = string.match

local fonts = fonts

local trace_goodies      = false  trackers.register("fonts.goodies", function(v) trace_goodies = v end)
local report_goodies     = logs.reporter("fonts","goodies")

local registerotffeature = fonts.handlers.otf.features.register

local fontgoodies        = fonts.goodies or { }

local fontcharacters     = fonts.hashes.characters

local trace_defining     = false  trackers.register("math.defining",   function(v) trace_defining   = v end)

local report_math        = logs.reporter("mathematics","initializing")

local nuts               = nodes.nuts

local setlink            = nuts.setlink

local nodepool           = nuts.pool

local new_kern           = nodepool.kern
local new_glyph          = nodepool.glyph
local new_hlist          = nodepool.hlist
local new_vlist          = nodepool.vlist

local insertnodeafter    = nuts.insertafter

local helpers            = fonts.helpers
local upcommand          = helpers.commands.up
local rightcommand       = helpers.commands.right
local charcommand        = helpers.commands.char
local prependcommands    = helpers.prependcommands

-- experiment, we have to load the definitions immediately as they precede
-- the definition so they need to be initialized in the typescript

local function withscriptcode(tfmdata,unicode,data,action)
    if type(unicode) == "string" then
        local p, u = match(unicode,"^(.-):(.-)$")
        if u then
            u = tonumber(u)
            if u then
                local slots = fonts.helpers.mathscriptslots(tfmdata,u)
                if slots then
                    if p == "*" then
                        action(u,data)
                        for i=1,#slots do
                            action(slots[i],data)
                        end
                    else
                        p = tonumber(p)
                        if p then
                            action(slots[p],data)
                        end
                    end
                end
            end
        end
    else
        action(unicode,data)
    end
end

local function finalize(tfmdata,feature,value)
--     if tfmdata.mathparameters then -- funny, cambria text has this
    local goodies = tfmdata.goodies
    if goodies then
        local virtualized = mathematics.virtualized
        for i=1,#goodies do
            local goodie = goodies[i]
            local mathematics = goodie.mathematics
            local dimensions  = mathematics and mathematics.dimensions
            if dimensions then
                if trace_defining then
                    report_math("overloading dimensions in %a @ %p",tfmdata.properties.fullname,tfmdata.parameters.size)
                end
                local characters   = tfmdata.characters
                local descriptions = tfmdata.descriptions
                local parameters   = tfmdata.parameters
                local factor       = parameters.factor
                local hfactor      = parameters.hfactor
                local vfactor      = parameters.vfactor
                local function overloadone(unicode,data)
                    local character = characters[unicode]
                    if not character then
                        local c = virtualized[unicode]
                        if c then
                            character = characters[c]
                        end
                    end
                    if character then
                        local width  = data.width
                        local height = data.height
                        local depth  = data.depth
                        if trace_defining and (width or height or depth) then
                            report_math("overloading dimensions of %C, width %p, height %p, depth %p",
                                unicode,width or 0,height or 0,depth or 0)
                        end
                        if width  then character.width  = width  * hfactor end
                        if height then character.height = height * vfactor end
                        if depth  then character.depth  = depth  * vfactor end
                        --
                        local xoffset = data.xoffset
                        local yoffset = data.yoffset
                        if xoffset == "llx" then
                            local d = descriptions[unicode]
                            if d then
                                xoffset         = - d.boundingbox[1] * hfactor
                                character.width = character.width + xoffset
                                xoffset         = rightcommand[xoffset]
                            else
                                xoffset = nil
                            end
                        elseif xoffset and xoffset ~= 0 then
                            xoffset = rightcommand[xoffset * hfactor]
                        else
                            xoffset = nil
                        end
                        if yoffset and yoffset ~= 0 then
                            yoffset = upcommand[yoffset * vfactor]
                        else
                            yoffset = nil
                        end
                        if xoffset or yoffset then
                            local commands = characters.commands
                            if commands then
                                prependcommands(commands,yoffset,xoffset)
                            else
                                local slot = charcommand[unicode]
                                if xoffset and yoffset then
                                    character.commands = { xoffset, yoffset, slot }
                                elseif xoffset then
                                    character.commands = { xoffset, slot }
                                else
                                    character.commands = { yoffset, slot }
                                end
                            end
                        end
                    elseif trace_defining then
                        report_math("no overloading dimensions of %C, not in font",unicode)
                    end
                end
                local function overload(dimensions)
                    for unicode, data in next, dimensions do
                        withscriptcode(tfmdata,unicode,data,overloadone)
                    end
                end
                if value == nil then
                    value = { "default" }
                end
                if value == "all" or value == true then
                    for name, value in next, dimensions do
                        overload(value)
                    end
                else
                    if type(value) == "string" then
                        value = utilities.parsers.settings_to_array(value)
                    end
                    if type(value) == "table" then
                        for i=1,#value do
                            local d = dimensions[value[i]]
                            if d then
                                overload(d)
                            end
                        end
                    end
                end
            end
        end
    end
end

registerotffeature {
    name         = "mathdimensions",
    description  = "manipulate math dimensions",
 -- default      = true,
    manipulators = {
        base = finalize,
        node = finalize,
    }
}

local function initialize(goodies)
    local mathgoodies = goodies.mathematics
    if mathgoodies then
        local virtuals = mathgoodies.virtuals
        local mapfiles = mathgoodies.mapfiles
        local maplines = mathgoodies.maplines
        if virtuals then
            for name, specification in next, virtuals do
                -- beware, they are all constructed ... we should be more selective
                mathematics.makefont(name,specification,goodies)
            end
        end
        if mapfiles then
            for i=1,#mapfiles do
                fonts.mappings.loadfile(mapfiles[i]) -- todo: backend function
            end
        end
        if maplines then
            for i=1,#maplines do
                fonts.mappings.loadline(maplines[i]) -- todo: backend function
            end
        end
    end
end

fontgoodies.register("mathematics", initialize)

-- local enabled = false   directives.register("fontgoodies.mathkerning",function(v) enabled = v end)

local function initialize(tfmdata)
--     if enabled and tfmdata.mathparameters then -- funny, cambria text has this
    if tfmdata.mathparameters then -- funny, cambria text has this
        local goodies = tfmdata.goodies
        if goodies then
            local characters = tfmdata.characters
            if characters[0x1D44E] then -- 119886
                -- we have at least an italic a
                for i=1,#goodies do
                    local mathgoodies = goodies[i].mathematics
                    if mathgoodies then
                        local kerns = mathgoodies.kerns
                        if kerns then
                            local function kernone(unicode,data)
                                local chardata = characters[unicode]
                                if chardata and (not chardata.mathkerns or data.force) then
                                    chardata.mathkerns = data
                                end
                            end
                            for unicode, data in next, kerns do
                                withscriptcode(tfmdata,unicode,data,kernone)
                            end
                            return
                        end
                    end
                end
            else
                return -- no proper math font anyway
            end
        end
    end
end

registerotffeature {
    name         = "mathkerns",
    description  = "math kerns",
 -- default      = true,
    initializers = {
        base = initialize,
        node = initialize,
    }
}

-- math italics (not really needed)
--
-- it would be nice to have a \noitalics\font option

local function initialize(tfmdata)
    local goodies = tfmdata.goodies
    if goodies then
        local shared = tfmdata.shared
        for i=1,#goodies do
            local mathgoodies = goodies[i].mathematics
            if mathgoodies then
                local mathitalics = mathgoodies.italics
                if mathitalics then
                    local properties = tfmdata.properties
                    if properties.setitalics then
                        mathitalics = mathitalics[file.nameonly(properties.name)] or mathitalics
                        if mathitalics then
                            if trace_goodies then
                                report_goodies("loading mathitalics for font %a",properties.name)
                            end
                            local corrections   = mathitalics.corrections
                            local defaultfactor = mathitalics.defaultfactor
                         -- properties.mathitalic_defaultfactor = defaultfactor -- we inherit outer one anyway (name will change)
                            if corrections then
                                fontgoodies.registerpostprocessor(tfmdata, function(tfmdata) -- this is another tfmdata (a copy)
                                    -- better make a helper so that we have less code being defined
                                    local properties = tfmdata.properties
                                    local parameters = tfmdata.parameters
                                    local characters = tfmdata.characters
                                    properties.mathitalic_defaultfactor = defaultfactor
                                    properties.mathitalic_defaultvalue  = defaultfactor * parameters.quad
                                    if trace_goodies then
                                        report_goodies("assigning mathitalics for font %a",properties.name)
                                    end
                                    local quad    = parameters.quad
                                    local hfactor = parameters.hfactor
                                    for k, v in next, corrections do
                                        local c = characters[k]
                                        if c then
                                            if v > -1 and v < 1 then
                                                c.italic = v * quad
                                            else
                                                c.italic = v * hfactor
                                            end
                                        else
                                            report_goodies("invalid mathitalics entry %U for font %a",k,properties.name)
                                        end
                                    end
                                end)
                            end
                            return -- maybe not as these can accumulate
                        end
                    end
                end
            end
        end
    end
end

registerotffeature {
    name         = "mathitalics",
    description  = "additional math italic corrections",
 -- default      = true,
    initializers = {
        base = initialize,
        node = initialize,
    }
}

-- fontgoodies.register("mathitalics", initialize)

local function mathradicalaction(n,h,v,font,mchar,echar)
    local characters = fontcharacters[font]
    local mchardata  = characters[mchar]
    local echardata  = characters[echar]
    local ewidth     = echardata.width
    local mwidth     = mchardata.width
    local delta      = h - ewidth
    local glyph      = new_glyph(font,echar)
    local head       = glyph
    if delta > 0 then
        local count = ceil(delta/mwidth)
        local kern  = (delta - count * mwidth) / count
        for i=1,count do
            local k = new_kern(kern)
            local g = new_glyph(font,mchar)
            setlink(k,head)
            setlink(g,k)
            head = g
        end
    end
    local height = mchardata.height
    local list   = new_hlist(head)
    local kern   = new_kern(height-v)
    list = setlink(kern,list)
    local list = new_vlist(kern)
    insertnodeafter(n,n,list)
end

local function mathhruleaction(n,h,v,font,bchar,mchar,echar)
    local characters = fontcharacters[font]
    local bchardata  = characters[bchar]
    local mchardata  = characters[mchar]
    local echardata  = characters[echar]
    local bwidth     = bchardata.width
    local mwidth     = mchardata.width
    local ewidth     = echardata.width
    local delta      = h - ewidth - bwidth
    local glyph      = new_glyph(font,echar)
    local head       = glyph
    if delta > 0 then
        local count = ceil(delta/mwidth)
        local kern  = (delta - count * mwidth) / (count+1)
        for i=1,count do
            local k = new_kern(kern)
            local g = new_glyph(font,mchar)
            setlink(k,head)
            setlink(g,k)
            head = g
        end
        local k = new_kern(kern)
        setlink(k,head)
        head = k
    end
    local g = new_glyph(font,bchar)
    setlink(g,head)
    head = g
    local height = mchardata.height
    local list   = new_hlist(head)
    local kern   = new_kern(height-v)
    list = setlink(kern,list)
    local list = new_vlist(kern)
    insertnodeafter(n,n,list)
end

local function initialize(tfmdata)
    local goodies = tfmdata.goodies
    if goodies then
        local resources = tfmdata.resources
        local ruledata  = { }
        for i=1,#goodies do
            local mathematics = goodies[i].mathematics
            if mathematics then
                local rules = mathematics.rules
                if rules then
                    for tag, name in next, rules do
                        ruledata[tag] = name
                    end
                end
            end
        end
        if next(ruledata) then
            local characters = tfmdata.characters
            local unicodes   = resources.unicodes
            if characters and unicodes then
                local mathruleactions = resources.mathruleactions
                if not mathruleactions then
                    mathruleactions = { }
                    resources.mathruleactions = mathruleactions
                end
                --
                local mchar = unicodes[ruledata["radical.extender"] or false]
                local echar = unicodes[ruledata["radical.end"]      or false]
                if mchar and echar then
                    mathruleactions.radicalaction = function(n,h,v,font)
                        mathradicalaction(n,h,v,font,mchar,echar)
                    end
                end
                --
                local bchar = unicodes[ruledata["hrule.begin"]    or false]
                local mchar = unicodes[ruledata["hrule.extender"] or false]
                local echar = unicodes[ruledata["hrule.end"]      or false]
                if bchar and mchar and echar then
                    mathruleactions.hruleaction = function(n,h,v,font)
                        mathhruleaction(n,h,v,font,bchar,mchar,echar)
                    end
                end
                -- not that nice but we need to register it at the tex end
             -- context.enablemathrules("\\fontclass")
            end
        end
    end
end

registerotffeature {
    name         = "mathrules",
    description  = "check math rules",
    default      = true,
    initializers = {
        base = initialize,
        node = initialize,
    }
}
