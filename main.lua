-- ============================================================
-- Стиль армирования колонны: ColumnSingleRebars
-- Продольные стержни по углам + поперечные стержни по X и Y
-- с раскладкой по высоте и опциональным выпуском продольных.
-- Локальная СК: центр нижней грани, OZ' вдоль оси колонны.
-- ============================================================

function isSupportedProfile(profile)
  return GetTypeName(profile) == "RectangularProfile"
end

function getRebarRadius(rebarStyleId)
  local style = GetRebarStyle(rebarStyleId)
  return GetParameterValue(style, "RebarDiameter") / 2
end

function getTransverseRebarOffset(sideClearCover,
                                  transverseFreeEnd,
                                  transverseRebarRadius)
  return sideClearCover + transverseFreeEnd + transverseRebarRadius
end

function getLongitudinalRebarOffset(sideClearCover,
                                    transverseFreeEnd,
                                    transverseRebarDiameter,
                                    longitudinalRebarRadius)
  return sideClearCover + transverseFreeEnd + transverseRebarDiameter + longitudinalRebarRadius
end

-- ------------------------------------------------------------
-- Колбэк управления состояниями параметров в диалоге стиля.
-- ------------------------------------------------------------
function SetStyleParameterStates(parameters)
  local values = parameters:GetParameterValues()
  local hasTopOverhang = values.CageLongitudinalRebars.TopOverhangEnabled
  parameters:GetParameter("CageLongitudinalRebars", "TopOverhang"):SetVisible(hasTopOverhang)
  parameters:GetParameter("ClearCovers", "TopClearCover"):SetVisible(not hasTopOverhang)
end

-- ------------------------------------------------------------
-- Точка входа, вызываемая Renga.
-- ------------------------------------------------------------
function CreateObjectReinforcement(object, styleParameters)
  local result = ReinforcementContainer()

  local profile = GetSectionProfile(object)
  if not isSupportedProfile(profile) then
    return result
  end

  -- Защитные слои
  local sideCover   = styleParameters.ClearCovers.SideClearCover
  local bottomCover = styleParameters.ClearCovers.BottomClearCover
  local topCover    = styleParameters.ClearCovers.TopClearCover

  -- Продольная арматура
  local longitudinalRebarStyleId = styleParameters.CageLongitudinalRebars.RebarStyleId
  local longitudinalFreeEnd      = styleParameters.CageLongitudinalRebars.FreeEnd
  local topOverhangEnabled       = styleParameters.CageLongitudinalRebars.TopOverhangEnabled
  local topOverhang              = styleParameters.CageLongitudinalRebars.TopOverhang

  -- Поперечная арматура
  local transverseRebarStyleId = styleParameters.CageTransverseRebars.RebarStyleId
  local transverseFreeEnd      = styleParameters.CageTransverseRebars.FreeEnd
  local transverseStep         = styleParameters.CageTransverseRebars.Step

  -- Радиусы стержней
  local longitudinalRebarRadius = getRebarRadius(longitudinalRebarStyleId)
  local transverseRebarRadius   = getRebarRadius(transverseRebarStyleId)
  local transverseRebarDiameter = transverseRebarRadius * 2

  -- Параметры объекта
  local columnHeight = GetParameterValue(object, "ColumnHeight")

  -- Размеры сечения
  local halfWidth = profile.Width / 2
  local halfDepth = profile.Height / 2

  -- ---- Продольные стержни ----
  local longOffset = getLongitudinalRebarOffset(
    sideCover,
    transverseFreeEnd,
    transverseRebarDiameter,
    longitudinalRebarRadius
  )

  if longOffset >= halfWidth or longOffset >= halfDepth then
    return result
  end

  local cornerX = halfWidth - longOffset
  local cornerY = halfDepth - longOffset

  if cornerX <= 0 or cornerY <= 0 then
    return result
  end

  local zBottomLong = bottomCover
  local zTopLong    = columnHeight - topCover
  if topOverhangEnabled then
    zTopLong = zTopLong + topOverhang
  end

  if zTopLong <= zBottomLong then
    return result
  end

  local baseCurve = CreateLineSegment3D(
    Point3D(0, 0, zBottomLong),
    Point3D(0, 0, zTopLong)
  )

  local corners = {
    { x = -cornerX, y = -cornerY },
    { x = -cornerX, y =  cornerY },
    { x =  cornerX, y = -cornerY },
    { x =  cornerX, y =  cornerY },
  }

  for _, c in ipairs(corners) do
    result:AddRebar(longitudinalRebarStyleId, baseCurve:Clone():Shift(c.x, c.y, 0))
  end

  -- ---- Поперечные стержни ----
  local transverseOffset = getTransverseRebarOffset(sideCover,
                                                    transverseFreeEnd,
                                                    transverseRebarRadius)

  local transverseHalfWidth = halfWidth - transverseOffset
  local transverseHalfDepth = halfDepth - transverseOffset

  if transverseHalfWidth <= 0 or transverseHalfDepth <= 0 then
    return result
  end

  -- Начальные Z для X- и Y-стержней
  local firstZAlongX = bottomCover + longitudinalFreeEnd + transverseRebarRadius
  local firstZAlongY = bottomCover + longitudinalFreeEnd + transverseRebarRadius * 3

  -- Верхняя граница раскладки (в выпуск поперечные не заходят)
  local lastZ = columnHeight - topCover - longitudinalFreeEnd - transverseRebarRadius

  if lastZ <= firstZAlongX or lastZ <= firstZAlongY then
    return result
  end

  local xStart = -halfWidth + sideCover
  local xEnd   =  halfWidth - sideCover
  local yStart = -halfDepth + sideCover
  local yEnd   =  halfDepth - sideCover

  -- X-стержни: раскладка по Z с шагом transverseStep
  local z = firstZAlongX
  while z <= lastZ do
    result:AddRebar(transverseRebarStyleId, CreateLineSegment3D(
      Point3D(xStart, -transverseHalfDepth, z),
      Point3D(xEnd,   -transverseHalfDepth, z)
    ))
    result:AddRebar(transverseRebarStyleId, CreateLineSegment3D(
      Point3D(xStart, transverseHalfDepth, z),
      Point3D(xEnd,   transverseHalfDepth, z)
    ))
    z = z + transverseStep
  end

  -- Y-стержни: раскладка по Z со сдвигом на диаметр
  z = firstZAlongY
  while z <= lastZ do
    result:AddRebar(transverseRebarStyleId, CreateLineSegment3D(
      Point3D(-transverseHalfWidth, yStart, z),
      Point3D(-transverseHalfWidth, yEnd,   z)
    ))
    result:AddRebar(transverseRebarStyleId, CreateLineSegment3D(
      Point3D(transverseHalfWidth, yStart, z),
      Point3D(transverseHalfWidth, yEnd,   z)
    ))
    z = z + transverseStep
  end

  return result
end