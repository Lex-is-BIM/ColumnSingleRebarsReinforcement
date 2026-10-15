-- ============================================================
-- Стиль армирования колонны: ColumnSingleRebars
-- Продольные стержни по углам + поперечные стержни по X и Y.
-- ============================================================

function isSupportedProfile(profile)
  return GetTypeName(profile) == "RectangularProfile"
end

function getRebarDiameter(rebarStyleId)
  local style = GetRebarStyle(rebarStyleId)
  return GetParameterValue(style, "RebarDiameter")
end

function getRebarRadius(rebarStyleId)
  return getRebarDiameter(rebarStyleId) / 2
end

function getTransverseRebarOffset(sideClearCover, transverseRebarRadius)
  return sideClearCover + transverseRebarRadius
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
-- Раскладка стержней по Z внутри отрезка fullLength.
-- Первый стержень на freeEnd от начала, последний на fullLength - freeEnd.
-- ------------------------------------------------------------
function createRebarLayoutWithFreeEnd(container, rebarStyleId,
                                      curve3D, fullLength, freeEnd, step)
  local rebarRadius = getRebarRadius(rebarStyleId)

  local length   = fullLength - freeEnd * 2
  local number   = math.floor(length / step)
  local lastStep = length - step * number

  if lastStep < rebarRadius * 2 then
    number = number - 1
  end

  -- Первый стержень: сдвиг на freeEnd от начала
  curve3D:Shift(0, 0, freeEnd)
  number = number + 1

  if number < 5 then
    local curve = curve3D:Clone()
    for _ = 1, number do
      container:AddRebar(rebarStyleId, curve)
      curve:Shift(0, 0, step)
    end
  else
    container:AddRebarSet(rebarStyleId, curve3D, Vector3D(0, 0, 1), step, number)
  end

  -- Последний стержень: на fullLength - freeEnd
  curve3D:Shift(0, 0, length)
  container:AddRebar(rebarStyleId, curve3D)
end

-- ------------------------------------------------------------
-- 4 продольных стержня по углам прямоугольного сечения.
-- ------------------------------------------------------------
function createLongitudinalRebars(container, rebarStyleId,
                                  halfWidth, halfDepth,
                                  offset,
                                  zBottom, zTop)
  local cornerX = halfWidth - offset
  local cornerY = halfDepth - offset

  if cornerX <= 0 or cornerY <= 0 then return end
  if zTop <= zBottom then return end

  local baseCurve = CreateLineSegment3D(
    Point3D(0, 0, zBottom),
    Point3D(0, 0, zTop)
  )

  local corners = {
    { x = -cornerX, y = -cornerY },
    { x = -cornerX, y =  cornerY },
    { x =  cornerX, y = -cornerY },
    { x =  cornerX, y =  cornerY },
  }

  for _, c in ipairs(corners) do
    container:AddRebar(rebarStyleId, baseCurve:Clone():Shift(c.x, c.y, 0))
  end
end

-- ------------------------------------------------------------
-- Поперечные стержни, параллельные оси X.
-- fullLength = columnHeight - topCover - bottomCover.
-- freeEnd    = bottomCover + longitudinalFreeEnd + transverseRebarRadius.
-- ------------------------------------------------------------
function createTransverseRebarsAlongX(container, rebarStyleId,
                                      halfWidth, halfDepth,
                                      columnHeight,
                                      bottomCover, topCover,
                                      sideClearCover,
                                      transverseFreeEnd,
                                      longitudinalFreeEnd,
                                      transverseRebarRadius,
                                      step)
  local xStart = -halfWidth + sideClearCover
  local xEnd   =  halfWidth - sideClearCover

  local yOffset = halfDepth
                - getTransverseRebarOffset(sideClearCover, transverseRebarRadius)
                - transverseFreeEnd

  if xEnd <= xStart or yOffset <= 0 then return end

  local fullLength = columnHeight - topCover - bottomCover
  if fullLength <= 0 then return end

  local freeEnd = bottomCover + longitudinalFreeEnd + transverseRebarRadius

  local curveMinusY = CreateLineSegment3D(
    Point3D(xStart, -yOffset, 0),
    Point3D(xEnd,   -yOffset, 0)
  )
  createRebarLayoutWithFreeEnd(container, rebarStyleId,
                               curveMinusY, fullLength, freeEnd, step)

  local curvePlusY = CreateLineSegment3D(
    Point3D(xStart,  yOffset, 0),
    Point3D(xEnd,    yOffset, 0)
  )
  createRebarLayoutWithFreeEnd(container, rebarStyleId,
                               curvePlusY, fullLength, freeEnd, step)
end

-- ------------------------------------------------------------
-- Поперечные стержни, параллельные оси Y.
-- fullLength = columnHeight - topCover - bottomCover.
-- freeEnd    = bottomCover + longitudinalFreeEnd + transverseRebarRadius * 3.
-- ------------------------------------------------------------
function createTransverseRebarsAlongY(container, rebarStyleId,
                                      halfWidth, halfDepth,
                                      columnHeight,
                                      bottomCover, topCover,
                                      sideClearCover,
                                      transverseFreeEnd,
                                      longitudinalFreeEnd,
                                      transverseRebarRadius,
                                      step)
  local yStart = -halfDepth + sideClearCover
  local yEnd   =  halfDepth - sideClearCover

  local xOffset = halfWidth
                - getTransverseRebarOffset(sideClearCover, transverseRebarRadius)
                - transverseFreeEnd

  if yEnd <= yStart or xOffset <= 0 then return end

  local fullLength = columnHeight - topCover - bottomCover
  if fullLength <= 0 then return end

  local freeEnd = bottomCover + longitudinalFreeEnd + transverseRebarRadius * 3

  local curveMinusX = CreateLineSegment3D(
    Point3D(-xOffset, yStart, 0),
    Point3D(-xOffset, yEnd,   0)
  )
  createRebarLayoutWithFreeEnd(container, rebarStyleId,
                               curveMinusX, fullLength, freeEnd, step)

  local curvePlusX = CreateLineSegment3D(
    Point3D( xOffset, yStart, 0),
    Point3D( xOffset, yEnd,   0)
  )
  createRebarLayoutWithFreeEnd(container, rebarStyleId,
                               curvePlusX, fullLength, freeEnd, step)
end

-- ------------------------------------------------------------
-- Параметрическое армирование колонны.
-- ------------------------------------------------------------
function parametricReinforcement(object, styleParameters)
  local result = ReinforcementContainer()

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

  -- Профиль (гарантированно прямоугольник)
  local profile   = GetSectionProfile(object)
  local halfWidth = profile.Width / 2
  local halfDepth = profile.Height / 2

  -- Смещение продольного стержня от грани
  local offset = getLongitudinalRebarOffset(
    sideCover,
    transverseFreeEnd,
    transverseRebarDiameter,
    longitudinalRebarRadius
  )

  if offset >= halfWidth or offset >= halfDepth then
    return result
  end

  -- Диапазон продольных стержней по Z
  local zBottom = bottomCover
  local zTop    = columnHeight - topCover

  if topOverhangEnabled then
    zTop = zTop + topOverhang
  end

  if zTop <= zBottom then
    return result
  end

  -- Продольные стержни по углам
  createLongitudinalRebars(result,
                           longitudinalRebarStyleId,
                           halfWidth, halfDepth,
                           offset,
                           zBottom, zTop)

  -- Поперечные стержни по X
  createTransverseRebarsAlongX(result,
                               transverseRebarStyleId,
                               halfWidth, halfDepth,
                               columnHeight,
                               bottomCover, topCover,
                               sideCover,
                               transverseFreeEnd,
                               longitudinalFreeEnd,
                               transverseRebarRadius,
                               transverseStep)

  -- Поперечные стержни по Y
  createTransverseRebarsAlongY(result,
                               transverseRebarStyleId,
                               halfWidth, halfDepth,
                               columnHeight,
                               bottomCover, topCover,
                               sideCover,
                               transverseFreeEnd,
                               longitudinalFreeEnd,
                               transverseRebarRadius,
                               transverseStep)

  return result
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

  return parametricReinforcement(object, styleParameters)
end