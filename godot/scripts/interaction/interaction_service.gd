class_name InteractionService
extends RefCounted


func interact(landmark: Dictionary, state: Dictionary) -> Dictionary:
	var id: String = str(landmark.get("id", ""))
	var result: Dictionary = {
		"kind": "inspect",
		"title": str(landmark.get("label", "现场记录")),
		"text": str(landmark.get("description", "没有发现可验证的新线索。")),
	}
	var repairs: Dictionary = state.get("repairs", {}) as Dictionary
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	var photos: Dictionary = state.get("photos", {}) as Dictionary
	match id:
		"repair_orders":
			flags["repair_orders_read"] = true
			GameManager.add_journal("order", "接受三份维修委托：主钟、礼拜堂六声钟、港口潮汐钟。", true)
			result["title"] = "三份维修委托"
			result["text"] = "三张纸使用不同部门的抬头，却都在 SATURDAY 06:00 同一刻签发。地图旁注标出广场、礼拜堂与港口。"
		"player_journal":
			result = {"kind": "journal", "tab": "journal"}
		"inn_ledger":
			KnowledgeManager.add_evidence(state, "ledger_gap", "旅店登记簿在六号与八号之间缺失一整行；这不是编号错误。")
			result["title"] = "登记簿缺失行"
			result["text"] = "墨线没有涂改，整条纸纤维被精确挖去。六号房后的走笔原本还要继续，八号房却换了一次蘸墨。"
		"installation_wrench_pickup":
			_pickup(state, "installation_wrench", "多萝西娅把市政安装扳手交给你；柄端有一个三角缺口。")
			result["title"] = "安装扳手"
			result["text"] = "三份维修单都允许使用它。工具本身普通，柄端的三角缺口却不像握柄设计；档案馆也许能鉴定。"
		"unnumbered_key_rack":
			result["text"] = "它已经由多萝西娅交给你。" if InventoryManager.has_item(state, "unnumbered_key") else "它挂在七号钩与八号钩之间。只说出‘七号房’不足以让多萝西娅交出钥匙。"
		"square_clock_face", "master_clock_mechanism":
			if bool(repairs.get("master", false)):
				result["title"] = "重新运转的主钟"
				result["text"] = "三枚红线每转一周都同时经过十二点；第七拍仍在机芯深处产生极轻的空响。"
			else:
				result = {"kind": "puzzle", "puzzle": "master"}
		"master_console":
			if not bool(repairs.get("master", false)):
				result["text"] = "主钟没有动力，记录滚筒无法前进。先修复三齿轮机构。"
			else:
				KnowledgeManager.add_evidence(state, "master_ar_record", "主钟控制台恢复后显示：A.R.，七次连续击发确认终止。")
				result["title"] = "A.R. 终止记录"
				result["text"] = "记录滚筒写着 A.R. / SEVEN CONSECUTIVE STRIKES CONFIRM TERMINATION。第七个信号位的铭牌已被拆除。"
		"silver_tuning_fork_pickup":
			_pickup(state, "silver_tuning_fork", "在主钟舱地面捡到刻着 VII 的银色音叉。")
			result["title"] = "银色音叉"
			result["text"] = "它不属于主钟标准工具组。轻敲时，钟楼方向传来几乎同频的金属共振。"
		"chapel_clock_mechanism":
			if bool(repairs.get("chapel", false)):
				result["text"] = "六枚钟锤已按同一节拍工作；独立第七锤仍不在这条传动链上。"
			else:
				result = {"kind": "puzzle", "puzzle": "chapel"}
		"missing_pin":
			_pickup(state, "chapel_pin", "在礼拜堂长椅下找到第四枚擒纵销。")
			result["title"] = "黄铜擒纵销"
			result["text"] = "普通维修件，尺寸与六锤机构的第四个空槽完全吻合。"
		"chapel_rope":
			result["text"] = "拉下绳索，六声铜音依次越过屋梁；第六声后，上方另有一枚钟锤轻轻晃动。" if bool(repairs.get("chapel", false)) else "绳索只带出五声完整钟响，第四拍是木制限位器的空响。"
		"chapel_install_log":
			KnowledgeManager.add_evidence(state, "chapel_ar_log", "礼拜堂安装记录：A.R. 将屋顶反射器的灯塔光路引向中央广场。")
			result["title"] = "礼拜堂 A.R. 安装记录"
			result["text"] = "纸边孔位与主钟记录相同，但来自独立钟楼档案。路线图把灯塔、礼拜堂屋顶和广场画在一条折线上。"
		"room7_tag_pickup":
			_pickup(state, "room7_tag", "在钟楼地板缝里找到旅店七号房钥匙牌。")
			result["title"] = "七号房钥匙牌"
			result["text"] = "旧黄铜牌边缘因长期使用变得圆滑。把它带给旅店主人。"
		"seventh_hammer":
			result["text"] = "底座没有钟绳，只有一枚音叉形校准槽。它不用于报时，而在等待另一个系统的终止信号。"
		"spare_lens_pickup":
			_pickup(state, "spare_lens", "从港口沙滩捡到带双导轨的厚镜片。")
			result["title"] = "双槽备用镜片"
			result["text"] = "镜片能同时容纳主光与备用光，但这只是技术判断；档案馆能确认正式用途。"
		"tide_clock", "tide_test_console":
			if bool(repairs.get("tide", false)):
				result["text"] = "三枚刻度环现在跟随港外低、中、高三条真实水线；盘面标出 SUNDAY 02:00–03:00 最低潮窗口。"
			else:
				result = {"kind": "puzzle", "puzzle": "tide"}
		"lighthouse_router":
			result["text"] = "双槽镜已锁定，备用光路经旅店屋顶落在照相馆西墙。" if bool(flags.get("light_route_inn_studio", false)) else "这项操作必须由灯塔看守完成；带着已鉴定镜片和可核验路线与康拉德交谈。"
		"cave_negative_pickup":
			if not InventoryManager.has_item(state, "flashlight"):
				result["text"] = "没有定向光，无法判断那是胶片还是湿石片。"
			else:
				_pickup(state, "cave_negative", "在退潮洞穴取得受潮底片；乳剂里似乎有一名站在主钟前的人。")
				result["title"] = "受潮的旧底片"
				result["text"] = "手电斜光下可见明显重影。不要猜人脸；照相馆能核查重影、反差和反射。"
		"development_bench":
			if bool(photos.get("unfinished_portrait", false)):
				result["text"] = "底片已得到一张未完成肖像；面孔稳定了，身份仍不完整。"
			else:
				result["text"] = "把底片实物交给埃利亚斯并明确请求显影，工作台才会开始三步处理。"
		"studio_counterweight", "silver_salt_wall":
			result["text"] = "配重已升起；备用光让银盐结晶显成门框，无编号钥匙可以转动暗锁。" if bool(flags.get("hidden_darkroom_open", false)) else str(landmark.get("description", ""))
		"cross_reference_desk":
			result["text"] = "带齐本轮主钟 A.R. 记录、钟楼 A.R. 安装记录和已显影的残缺肖像，再与弗洛伦斯交谈。"
		"tool_identification_cards":
			result["text"] = "索引卡不会自行检查背包。必须与弗洛伦斯交谈，每次把一件实物放到卡旁，由她登记型号与用途。"
		"return_exposure_file":
			result["text"] = "档案正文需由弗洛伦斯当面查阅；向她询问‘回返曝光’或屋顶反射器。"
		"brake_interface":
			KnowledgeManager.add_evidence(state, "brake_interface", "地下室三角制动接口与安装扳手柄端吻合，但必须由维护负责人执行。")
			result["title"] = "主钟紧急制动接口"
			result["text"] = "机械接口与扳手完全吻合。程序牌要求维护负责人现场确认并执行，玩家不能绕过阿瑟。"
		"three_signal_lights":
			result["text"] = "灯塔光路：%s；主钟制动：%s；第七终钟：%s。机器要求对应居民亲自承诺。" % [
				"已确认" if bool(flags.get("conrad_routes_light", false)) else "未确认",
				"已确认" if bool(flags.get("arthur_stops_clock", false)) else "未确认",
				"已确认" if bool(flags.get("beatrice_rings_seventh", false)) else "未确认",
			]
		"witness_slot_seven":
			if bool(flags.get("slot_seven_filled", false)):
				result["text"] = "艾达·罗文的定影肖像已经稳定在槽内；七枚信号灯第一次同时稳定。"
			elif InventoryManager.has_item(state, "fixed_portrait"):
				DialogueManager.install_ada_portrait(state)
				AudioManager.play("event")
				result["text"] = "照片滑入卡槽，第七盏灯由白转金。红色删除杆断电，白色旋钮弹出。"
			else:
				result["text"] = "这里需要拥有姓名、住处、职责和面孔的完整见证人，不是任意照片。"
		"identity_fixing_table":
			result = {"kind": "inspect", "title": "身份定影台", "text": "艾达的四个身份锚点已经固定。"} if bool(photos.get("fixed_portrait", false)) else {"kind": "puzzle", "puzzle": "identity"}
		"ada_voice":
			result["text"] = "‘别把我当成一个秘密结局。我只是本来就住在这里的人。’" if bool(photos.get("fixed_portrait", false)) else "红灯闪动时，空白相纸背后传来一句不完整的话：‘不要只带着我的……名字……’"
		"red_erase_lever":
			if bool(flags.get("slot_seven_filled", false)):
				result["text"] = "第七见证记录已恢复，机器不再允许用缺席完成终止。"
			elif DialogueManager.surface_protocol_ready(state):
				result = {"kind": "ending", "ending": "surface"}
			else:
				result["text"] = "仍被三枚外部信号锁住。康拉德、阿瑟和贝娅特丽斯必须分别确认光路、停钟与第七声。"
		"white_continue_knob":
			result = {"kind": "ending", "ending": "true"} if bool(flags.get("slot_seven_filled", false)) else {"kind": "inspect", "title": "被遮住的白色旋钮", "text": "只有补回第七见证记录，内部机构才会推出旋钮。"}
	state["flags"] = flags
	TimeManager.sync_world_flags(state)
	return result


func _pickup(state: Dictionary, item_id: String, note: String) -> void:
	if not InventoryManager.has_item(state, item_id):
		InventoryManager.add_item(state, item_id)
		GameManager.add_journal("item", note, false)

