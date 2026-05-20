extends SceneTree


func _initialize() -> void:
	var indexer = load("res://scripts/core/memory/memory_vector_index.gd").new()
	var left: Array = indexer.embed_text("围棋布局需要先占角，厚势可以转化为中盘攻击。")
	var right: Array = indexer.embed_text("围棋布局先占角，厚势转化为攻击。")
	var unrelated: Array = indexer.embed_text("语音合成只负责文本转音频。")
	_expect(left.size() == 128, "local embedding dimension should be stable")
	_expect(indexer.cosine(left, right) > indexer.cosine(left, unrelated), "related memories should score higher than unrelated memories")

	var manager = load("res://scripts/core/memory/memory_manager.gd").new()
	manager.persistence_enabled = false
	manager.prefer_android_sqlite = false
	manager.load_or_create()
	var scope: Dictionary = manager.scope("bot_vector", "bot", "bot_vector", "profile")
	var update_result: Dictionary = manager.update_memory({
		"bot_id": "bot_vector",
		"scope": scope,
		"update_reason": "vector_check",
		"memory_update": {
			"visibility": "self_private",
			"episodic_events": [
				{
					"content": "围棋布局阶段先占角，再根据厚势选择中盘攻击。",
					"importance": 0.82,
					"confidence": 0.86,
				},
			],
			"semantic_candidates": [
				{
					"content": "厚势需要转化为实地、攻击或控场，不能只停留在形势判断。",
					"importance": 0.84,
					"confidence": 0.82,
					"status": "active",
				},
			],
			"reflection_candidates": [
				{
					"content": "如果布局只追求厚势而不转化，后续会失去主动权。",
					"importance": 0.76,
					"confidence": 0.78,
					"status": "active",
				},
			],
		},
	})
	_expect(bool(update_result.get("ok", false)), "memory update should succeed")
	var update_report: Dictionary = manager.get_last_update_report()
	var update_index_report: Dictionary = update_report.get("index_report", {}) as Dictionary
	_expect(String(update_index_report.get("embedding_model", "")) == "token_hash_v1", "update report should expose embedding model")
	_expect(int(update_index_report.get("event_vector_count", 0)) == 1, "update report should count event vectors")
	_expect(int(update_index_report.get("semantic_vector_count", 0)) >= 2, "update report should count semantic graph vectors")

	var index_status: Dictionary = manager.get_memory_index_status({"scope": scope}).get("data", {}) as Dictionary
	_expect(String(index_status.get("retrieval_mode", "")) == "hybrid_vector", "retrieval mode should be hybrid_vector when local index is ready")
	_expect(bool(index_status.get("vector_enabled", false)), "local vector index should be enabled")
	_expect(not bool(index_status.get("native_sqlite_vec_enabled", true)), "native sqlite-vec should stay false")
	_expect(not bool(index_status.get("native_hnswlib_enabled", true)), "native hnswlib should stay false")
	_expect(String(index_status.get("embedding_provider", "")) == "godot_local", "embedding provider should be local")
	_expect(int(index_status.get("hnsw_graph_nodes", 0)) >= 2, "semantic graph should have nodes")

	var context_result: Dictionary = manager.get_memory_context({
		"bot_id": "bot_vector",
		"scope": scope,
		"query": "围棋 厚势 布局 攻击",
		"memory_options": {"final_max_items": 8, "max_token_budget": 2048},
	})
	_expect(bool(context_result.get("ok", false)), "memory context should be built")
	var report: Dictionary = ((context_result.get("data", {}) as Dictionary).get("retrieval_report", {}) as Dictionary)
	var source_counts: Dictionary = (report.get("source_fetch_report", {}) as Dictionary).get("source_counts", {}) as Dictionary
	_expect(int(source_counts.get("sqlite_vec_event", 0)) >= 1, "episodic vector source should be labeled sqlite_vec_event")
	_expect(int(source_counts.get("hnsw_semantic", 0)) >= 1, "semantic vector source should be labeled hnsw_semantic")
	_expect(bool(report.get("vector_enabled", false)), "retrieval report should show vector enabled")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
