if not modules then modules = { } end modules ['anch-pgr'] = {
    version   = 1.001,
    comment   = "companion to anch-pgr.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local format = string.format
local concat, sort = table.concat, table.sort
local splitter = lpeg.splitat(":")
local lpegmatch = lpeg.match

local jobpositions = job.positions

local report_graphics = logs.reporter("graphics")

local function pair(x,y)
    return format("(%.5fpt,%.5fpt)",x/65536,y/65536)
end

local function path(t)
    return concat(t,"--") .. "--cycle"
end

local function regionarea(r)
    local rx, ry = r.x, r.y
    local rw = rx + r.w
    local rh = ry + r.h
    local rd = ry - r.d
    return {
        pair(rx, rh - ry),
        pair(rw, rh - ry),
        pair(rw, rd - ry),
        pair(rx, rd - ry),
    }
end

local function add(t,x,y)
    local last = t[#t]
    if not last or last[1] ~= x or last[2] ~= y then
        t[#t+1] = { x, y }
    end
end

local function clip(t,ytop,ybot)
    local first, last = 1, #t
    for i=first,last do
        local y = t[i][2]
        if ytop < y then
            first = i
        end
        if ybot > y then
            last = i
            break
        end
    end
    local lp = { }
    lp[#lp+1] = { t[first][1], ytop }
    for i=first+1,last-1 do
        lp[#lp+1] = { t[i][1], t[i][2] }
    end
    lp[#lp+1] = { t[last][1], ybot }
    return lp
end

local function shapes(r,rx,ry,rw,rh,rd,lytop,lybot,rytop,rybot)
    -- we assume that we only hang per page and not cross pages
    -- which makes sense as hanging is only uses in special cases
    --
    -- we can remove data as soon as a page is done so we could
    -- remember per page and discard areas after each shipout
    local paragraphs = r.paragraphs
    local left  = { { rx, rh } }
    local right = { { rw, rh } }
    local extending = false
    if paragraphs then
        for i=1,#paragraphs do
            local p = paragraphs[i]
            local ha = p.ha
            if ha and ha ~= 0 then
                local py = p.y
                local ph = p.h
                local pd = p.d
                local hi = p.hi
                local hang = ha * (ph + pd)
                local py_ph = py + ph
                -- ha < 0 hi < 0 : right top
                -- ha < 0 hi > 0 : left  top
                if ha < 0 then
                    if hi < 0 then -- right
                        add(right,rw     , py_ph)
                        add(right,rw + hi, py_ph)
                        add(right,rw + hi, py_ph + hang)
                        add(right,rw     , py_ph + hang)
                    else
                        -- left
                        add(left,rx,      py_ph)
                        add(left,rx + hi, py_ph)
                        add(left,rx + hi, py_ph + hang)
                        add(left,rx,      py_ph + hang)
                    end
                end
extending = false
            else -- we need to clip to the next par
                local ps = p.ps
                if ps then
                    local py = p.y
                    local ph = p.h
                    local pd = p.d
                    local step = ph + pd
                    local size = #ps * step
                    local py_ph = py + ph
                    add(left,rx,py_ph)
                    add(right,rw,py_ph)
                    for i=1,#ps do
                        local p = ps[i]
                        local l = p[1]
                        local w = p[2]
                        add(left,rx + l, py_ph)
                        add(right,rx + l + w, py_ph)
                        py_ph = py_ph - step
                        add(left,rx + l, py_ph)
                        add(right,rx + l + w, py_ph)
                    end
                    extending = true
--                     add(left,rx,py_ph)
--                     add(right,rw,py_ph)
                else
                    if extending then
                        local py = p.y
                        local ph = p.h
                        local pd = p.d
                        local py_ph = py + ph
                        local py_pd = py - pd
                        add(left,left[#left][1],py_ph)
                        add(right,right[#right][1],py_ph)
                        add(left,rx,py_ph)
                        add(right,rw,py_ph)
extending = false
                    end
                end
            end
        end
    end
    -- we can have a simple variant when no paragraphs
    if extending then
        -- not ok
        left[#left][2] = rd
        right[#right][2] = rw
    else
        add(left,rx,rd)
        add(right,rw,rd)
    end
    return clip(left,lytop,lybot), clip(right,rytop,rybot)
end

local function singlepart(b,e,r,left,right)
    local bx, by = b.x, b.y
    local ex, ey = e.x, e.y
    local rx, ry = r.x, r.y
    local rw = rx + r.w
    local rh = ry + r.h
    local rd = ry - r.d
    if left then
        rx = rx + left
        rw = rw - right
    end
    local bh = by + b.h
    local bd = by - b.d
    local eh = ey + e.h
    local ed = ey - e.d
    local area = { }
    local leftshapes, rightshapes = shapes(r,rx,ry,rw,rh,rd,bd,ed,bh,eh)
    add(area,bx,bh-ry)
    for i=1,#rightshapes do
        local ri = rightshapes[i]
        add(area,ri[1],ri[2]-ry)
    end
    add(area,ex,eh-ry)
    add(area,ex,ed-ry)
    for i=#leftshapes,1,-1 do
        local li = leftshapes[i]
        add(area,li[1],li[2]-ry)
    end
    add(area,bx,bd-ry)
    for i=1,#area do
        local a = area[i]
        area[i] = pair(a[1],a[2])
    end
    return { -- no collapsing yet
        location = "single",
        region   = r,
        area     = area,
    }
end

local function firstpart(b,r,left,right)
    local bx, by = b.x, b.y
    local rx, ry = r.x, r.y
    local rw = rx + r.w
    local rh = ry + r.h
    local rd = ry - r.d
    if left then
        rx = rx + left
        rw = rw - right
    end
    local bh = by + b.h
    local bd = by - b.d
    local area = { }
    local leftshapes, rightshapes = shapes(r,rx,ry,rw,rh,rd,bd,rd,bh,rd)
    add(area,bx,bh-ry)
    for i=1,#rightshapes do
        local ri = rightshapes[i]
        add(area,ri[1],ri[2]-ry)
    end
    for i=#leftshapes,1,-1 do
        local li = leftshapes[i]
        add(area,li[1],li[2]-ry)
    end
    add(area,bx,bd-ry)
    for i=1,#area do
        local a = area[i]
        area[i] = pair(a[1],a[2])
    end
    return {
        location = "first",
        region   = r,
        area     = area,
    }
end

local function middlepart(r,left,right)
    local rx, ry = r.x, r.y
    local rw = rx + r.w
    local rh = ry + r.h
    local rd = ry - r.d
    if left then
        rx = rx + left
        rw = rw - right
    end
    local area = { }
    local leftshapes, rightshapes = shapes(r,rx,ry,rw,rh,rd,rh,rd,rh,rd)
    for i=#leftshapes,1,-1 do
        local li = leftshapes[i]
        add(area,li[1],li[2]-ry)
    end
    for i=1,#rightshapes do
        local ri = rightshapes[i]
        add(area,ri[1],ri[2]-ry)
    end
    for i=1,#area do
        local a = area[i]
        area[i] = pair(a[1],a[2])
    end
    return {
        location = "middle",
        region   = r,
        area     = area,
    }
end

local function lastpart(e,r,left,right)
    local ex, ey = e.x, e.y
    local rx, ry = r.x, r.y
    local rw = rx + r.w
    local rh = ry + r.h
    local rd = ry - r.d
    if left then
        rx = rx + left
        rw = rw - right
    end
    local eh = ey + e.h
    local ed = ey - e.d
    local area = { }
    -- two cases: till end and halfway e line
    local leftshapes, rightshapes = shapes(r,rx,ry,rw,rh,rd,rh,ed,rh,eh)
    for i=1,#rightshapes do
        local ri = rightshapes[i]
        add(area,ri[1],ri[2]-ry)
    end
    add(area,ex,eh-ry)
    add(area,ex,ed-ry)
    for i=#leftshapes,1,-1 do
        local li = leftshapes[i]
        add(area,li[1],li[2]-ry)
    end
    for i=1,#area do
        local a = area[i]
        area[i] = pair(a[1],a[2])
    end
    return {
        location = "last",
        region   = r,
        area     = area,
    }
end

graphics = graphics or { }
local backgrounds = { }

graphics.backgrounds = backgrounds

local function calculate(tag)
    local collected = jobpositions.collected
    local b = collected[format("b:%s",tag)]
    local e = collected[format("e:%s",tag)]
    if not b or not e then
        report_graphics("invalid tag '%s'",tag)
        return { }
    end
    local br = b.r
    local er = e.r
    if not br or not er then
        report_graphics("invalid region for '%s'",tag)
        return { }
    end
    local btag, bindex = lpegmatch(splitter,br)
    local etag, eindex = lpegmatch(splitter,er)
    if not bindex or not eindex or btag ~= etag then
        report_graphics("invalid indices for '%s'",tag)
        return { }
    end
    local bindex = tonumber(bindex)
    local eindex = tonumber(eindex)
    -- Here we compensate for columns (in tables): a table can have a set of column
    -- entries and these are shared. We compensate left/right based on the columns
    -- x and w but need to take the region into acount where the specification was
    -- flushed and not the begin pos's region, because otherwise we get the wrong
    -- compensation for assymetrical doublesided layouts.
    local left = 0
    local right = 0
    local rc = b.c
    if rc then
        rc = collected[rc]
        if rc then
            local tb = collected[rc.r]
            if tb then
                left = -(tb.x - rc.x)
                right = (tb.w - rc.w - left) -- tb.x - rc.x
            end
        end
    end
    -- Obeying intermediate changes of left/rightskip makes no sense as it will
    -- look bad, so we only look at the begin situation.
    --
    local bn = b.n
    if bn then
        local bp = collected[format("p:%s",bn)]
        if bp then
            left  = left  + bp.ls
            right = right + bp.rs
        end
    end
    --
    if bindex == eindex then
        return {
            [b.p] = { singlepart(b,e,collected[br],left,right) }
        }
    else
        local pars = {
            [b.p] = { firstpart(b,collected[br],left,right) }
        }
        for i=bindex+1,eindex-1 do
            br = format("%s:%s",btag,i)
            local r = collected[br]
            if not r then
               report_graphics("invalid middle for '%s'",br)
            else
                local p = r.p
                local pp = pars[p]
                if pp then
                    pp[#pp+1] = middlepart(r,left,right)
                else
                    pars[p] = { middlepart(r,left,right) }
                end
            end
        end
        local p = e.p
        local pp = pars[p]
        if pp then
            pp[#pp+1] = lastpart(e,collected[er],left,right)
        else
            pars[p] = { lastpart(e,collected[er],left,right) }
        end
        return pars
    end
end

local pending = { } -- needs gc

local function register(data,n,anchor)
    local pa = pending[anchor]
    if not pa then
        pa = { }
        pending[anchor] = pa
    end
    for page, pagedata in next, data do
        local pap = pa[page]
        if pap then
            pap[#pap+1] = n
        else
            pa[page] = { n }
        end
    end
end

function graphics.backgrounds.registered(anchor,page)
    local pa = pending[anchor]
    if pa then
        concat(pa,",")
    else
        return ""
    end
end

local pbg = { } -- will move to pending

function graphics.backgrounds.calculate(n)
    if not pbg[n] then
        pbg[n] = calculate("pbg",n) or { }
    end
end

local multilocs = {
    single = 1, -- maybe 0
    first  = 1,
    middle = 2,
    last   = 3,
}

local template_a = [[
path multiregs[], multipars[], multibox ;
string multikind[] ;
numeric multilocs[], nofmultipars ;
nofmultipars := %s ;
multibox := unitsquare xyscaled %s ;
]]

local template_b = [[
multilocs[%s] := %s ;
multikind[%s] := "%s" ;
multipars[%s] := (%s) shifted - %s ;
]]

local template_c = [[
multiregs[%s] := (%s) shifted - %s ;
]]

local template_d = [[
setbounds currentpicture to multibox ;
]]

function graphics.backgrounds.fetch(n,page,anchor)
    local data = pbg[n]
    if not data then
        data = calculate(n)
        pbg[n] = data -- can be replaced by register
        register(data,n,anchor)
    end
    if data then
        local pagedata = data[page]
        if pagedata then
            local nofmultipars = #pagedata
--             report_graphics("fetching '%s' at page %s using anchor '%s' containing %s multipars",n,page,anchor,nofmultipars)
            local a = jobpositions.collected[anchor]
            if not a then
                report_graphics("missing anchor '%s'",anchor)
            else
                local trace = false
                local x, y, w, h, d = a.x, a.y, a.w, a.h, a.d
                local result = { format(template_a,nofmultipars,pair(w,h+d)) }
                for i=1,nofmultipars do
                    local region = pagedata[i]
                    result[#result+1] = format(template_b,
                        i, multilocs[region.location],
                        i, region.location,
                        i, path(region.area), pair(x,y-region.region.y))
                    if trace then
                        result[#result+1] = format(template_c,
                            i, path(regionarea(region.region)), offset)
                    end
                end
                data[page] = nil
                result[#result+1] = template_d
                result = concat(result,"\n")
                return result
            end
        end
    end
    return format(template_a,0,"origin")
end

function commands.fetchmultipar(n,page,anchor)
    context(graphics.backgrounds.fetch(n,page,anchor))
end

local doifelse = commands.doifelse

function commands.doifelsemultipar(n,page)
    local data = pbg[n]
    if not data then
        data = calculate(n)
        pbg[n] = data
    end
    if page then
        doifelse(data and data[page] and true)
    else
        doifelse(data and next(data) and true)
    end
end

function commands.doifelserangeonpage(first,last,page)
    local collected = jobpositions.collected
    local f = collected[first]
    if not f then
        doifelse(false)
        return
    end
    local l = collected[last]
    if not l then
        doifelse(false)
        return
    end
    doifelse(page >= f.p and page <= l.p)
end