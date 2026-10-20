-- Function for controlling the state of parameters in the style dialog.
function SetStyleParameterStates(parameters)
    local values = parameters:GetParameterValues()

    local hasTopOverhang = values.LongitudinalRebars.TopOverhangEnabled

    parameters:GetParameter("LongitudinalRebars", "TopOverhang"):SetVisible(hasTopOverhang)
    parameters:GetParameter("General", "TopClearCover"):SetVisible(not hasTopOverhang)
end

function getRebarRadius(rebarStyleId)
    local style = GetRebarStyle(rebarStyleId)
    return GetParameterValue(style, "RebarDiameter") / 2
end

-- Returns the offset of the transverse rebar from the side face.
function getTransverseRebarOffset(sideClearCover, transverseFreeEnd, transverseRebarRadius)
    return sideClearCover + transverseFreeEnd + transverseRebarRadius
end

-- Returns the offset of the longitudinal rebar from the side face.
function getLongitudinalRebarOffset(sideClearCover, transverseFreeEnd,
                                    transverseRebarDiameter, longitudinalRebarRadius)
    return sideClearCover + transverseFreeEnd + transverseRebarDiameter + longitudinalRebarRadius
end

-- Returns the coordinates of the four corner positions for the longitudinal bars
-- as a table with four points: left-bottom, left-top, right-bottom, right-top.
function getCornerPositions(halfWidth, halfDepth, offset)
    return {
        { x = -halfWidth + offset, y = -halfDepth + offset },
        { x = -halfWidth + offset, y =  halfDepth - offset },
        { x =  halfWidth - offset, y = -halfDepth + offset },
        { x =  halfWidth - offset, y =  halfDepth - offset }
    }
end

-- The function creates longitudinal rebars at the four corners of the column section.
-- container - Reinforcement container
-- rebarStyleId - the style ID of the rebar
-- halfWidth, halfDepth - the half the column width and depth
-- offset - the offset from the column face
-- bottomZ, topZ - bottom and top elevations of the longitudinal rebars
function createLongitudinalRebars(container, rebarStyleId,
                                  halfWidth, halfDepth,
                                  offset,
                                  bottomZ, topZ)
    local curve = CreateLineSegment3D(Point3D(0, 0, bottomZ), Point3D(0, 0, topZ))

    local corners = getCornerPositions(halfWidth, halfDepth, offset)
    for _, corner in ipairs(corners) do
        container:AddRebar(rebarStyleId, curve:Clone():Shift(corner.x, corner.y, 0))
    end
end

-- The function creates transverse rebars along the X and Y axes,
-- laid out along the column height with the specified step.
-- container - Reinforcement container
-- rebarStyleId - the style ID of the rebar
-- halfWidth, halfDepth - the half the column width and depth
-- sideCover - side clear cover
-- transverseHalfWidth, transverseHalfDepth - half sizes for transverse rebars
-- firstZAlongX, firstZAlongY - initial elevations for X and Y rebars
-- lastZ - upper bound of the layout
-- step - the layout step
function createTransverseRebars(container, rebarStyleId,
                                halfWidth, halfDepth,
                                sideCover,
                                transverseHalfWidth, transverseHalfDepth,
                                firstZAlongX, firstZAlongY,
                                lastZ, step)
    local xStart = -halfWidth + sideCover
    local xEnd   =  halfWidth - sideCover
    local yStart = -halfDepth + sideCover
    local yEnd   =  halfDepth - sideCover

    -- Rebars along X, laid out along Z
    local z = firstZAlongX
    while z <= lastZ do
        container:AddRebar(rebarStyleId, CreateLineSegment3D(
            Point3D(xStart, -transverseHalfDepth, z),
            Point3D(xEnd,   -transverseHalfDepth, z)
        ))
        container:AddRebar(rebarStyleId, CreateLineSegment3D(
            Point3D(xStart,  transverseHalfDepth, z),
            Point3D(xEnd,    transverseHalfDepth, z)
        ))
        z = z + step
    end

    -- Rebars along Y, laid out along Z with an offset by rebar diameter
    z = firstZAlongY
    while z <= lastZ do
        container:AddRebar(rebarStyleId, CreateLineSegment3D(
            Point3D(-transverseHalfWidth, yStart, z),
            Point3D(-transverseHalfWidth, yEnd,   z)
        ))
        container:AddRebar(rebarStyleId, CreateLineSegment3D(
            Point3D( transverseHalfWidth, yStart, z),
            Point3D( transverseHalfWidth, yEnd,   z)
        ))
        z = z + step
    end
end

-- The function creates object reinforcement and is called by Renga.
function CreateObjectReinforcement(object, styleParameters)
    local result = ReinforcementContainer()

    -- the example only for rectangular column profile
    local profile = GetSectionProfile(object)
    if GetTypeName(profile) ~= "RectangularProfile" then
        return result
    end

    -- clear covers
    local bottomCover = styleParameters.General.BottomClearCover
    local sideCover   = styleParameters.General.SideClearCover
    local topCover    = styleParameters.General.TopClearCover

    -- longitudinal rebars parameters
    local longitudinalRebarId  = styleParameters.LongitudinalRebars.RebarStyleId
    local longitudinalFreeEnd  = styleParameters.LongitudinalRebars.FreeEnd
    local topOverhangEnabled   = styleParameters.LongitudinalRebars.TopOverhangEnabled
    local topOverhang          = styleParameters.LongitudinalRebars.TopOverhang

    -- transverse rebars parameters
    local transverseRebarId   = styleParameters.TransverseRebars.RebarStyleId
    local transverseFreeEnd   = styleParameters.TransverseRebars.FreeEnd
    local transverseStep      = styleParameters.TransverseRebars.Step

    -- rebar radii
    local longitudinalRebarRadius = getRebarRadius(longitudinalRebarId)
    local transverseRebarRadius   = getRebarRadius(transverseRebarId)
    local transverseRebarDiameter = transverseRebarRadius * 2

    -- column parameters
    local columnHeight = GetParameterValue(object, "ColumnHeight")

    -- modified width and depth according clear cover values
    local halfWidth = profile.Width / 2
    local halfDepth = profile.Height / 2

    -- longitudinal rebars offset from the column face
    local longitudinalOffset = getLongitudinalRebarOffset(
        sideCover, transverseFreeEnd, transverseRebarDiameter, longitudinalRebarRadius)

    if longitudinalOffset >= halfWidth or longitudinalOffset >= halfDepth then
        return result
    end

    -- longitudinal rebars elevations
    local bottomZ = bottomCover
    local topZ    = columnHeight - topCover

    if topOverhangEnabled then
        topZ = topZ + topOverhang
    end

    if topZ <= bottomZ then
        return result
    end

    -- create longitudinal rebars
    createLongitudinalRebars(result, longitudinalRebarId,
                             halfWidth, halfDepth,
                             longitudinalOffset,
                             bottomZ, topZ)

    -- transverse rebars parameters
    local transverseOffset = getTransverseRebarOffset(sideCover, transverseFreeEnd, transverseRebarRadius)

    local transverseHalfWidth = halfWidth - transverseOffset
    local transverseHalfDepth = halfDepth - transverseOffset

    if transverseHalfWidth <= 0 or transverseHalfDepth <= 0 then
        return result
    end

    -- initial elevations for X and Y rebars
    local firstZAlongX = bottomCover + longitudinalFreeEnd + transverseRebarRadius
    local firstZAlongY = bottomCover + longitudinalFreeEnd + transverseRebarRadius * 3

    -- upper bound of the layout (transverse rebars do not go into the overhang)
    local lastZ = columnHeight - topCover - longitudinalFreeEnd - transverseRebarRadius

    if lastZ <= firstZAlongX or lastZ <= firstZAlongY then
        return result
    end

    -- create transverse rebars
    createTransverseRebars(result, transverseRebarId,
                           halfWidth, halfDepth,
                           sideCover,
                           transverseHalfWidth, transverseHalfDepth,
                           firstZAlongX, firstZAlongY,
                           lastZ, transverseStep)

    return result
end