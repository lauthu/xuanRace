class_name GpRoad
extends Node3D
## GP 赛道路面：运行时调用 Road Generator 插件生成
## 带车道线、路肩与碰撞体的专业公路网格。

const LANE_WIDTH := 12.0 ## 单车道宽（米）+ 两侧路肩各 2 米 = 16 米总宽
const SHOULDER_WIDTH := 2.0 ## 单侧路肩宽（米）
const SAMPLE_COUNT := 64 ## 中心线采样点数（决定分段粒度）


## 沿闭环中心线生成公路。points 不含重复终点。
func build(points: PackedVector2Array) -> void:
	var manager := RoadManager.new()
	manager.name = "GpRoadManager"
	add_child(manager)

	var container := RoadContainer.new()
	container.name = "RoadContainer"
	manager.add_child(container)

	var road_points: Array[RoadPoint] = []
	var n := points.size()
	for i in n:
		var rp := RoadPoint.new()
		container.add_child(rp)
		# 略高于地面，避免与地表 z-fighting（公路自带碰撞体）
		rp.position = Vector3(points[i].x, 0.02, points[i].y)
		rp.lanes = [RoadPoint.LaneType.SLOW]
		rp.lane_width = LANE_WIDTH
		rp.shoulder_width_l = SHOULDER_WIDTH
		rp.shoulder_width_r = SHOULDER_WIDTH
		# 关键：曲线手柄沿 RoadPoint 朝向（basis.z）生成，
		# 必须让点朝向中心线切线，否则曲线会失控鼓包
		var tangent := (points[(i + 1) % n] - points[(i - 1 + n) % n]).normalized()
		rp.rotation.y = atan2(tangent.x, tangent.y)
		road_points.append(rp)

	# 等一帧：RoadContainer._ready 中 setup_road_container 是延迟调用的，
	# 若立即连接会被它后续的自动整理覆盖，导致闭环断裂
	await get_tree().process_frame

	for i in n:
		var next := road_points[(i + 1) % n]
		road_points[i].connect_roadpoint(RoadPoint.PointInit.NEXT, next, RoadPoint.PointInit.PRIOR)

	container.rebuild_segments(true)
