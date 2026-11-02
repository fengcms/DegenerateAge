extends Node
## 诊断探针身份边界，正式项目和伪造共享user目录不能通过隔离判据。

## 纯判据不修改项目名，也不访问真实槽位。
func _ready() -> void:
	assert(DiagnosticProbeGuard.is_isolated(), "测试运行器应提供真正隔离身份")
	assert(not DiagnosticProbeGuard.isolated_identity("末法纪元",false,"/tmp/末法纪元"))
	assert(not DiagnosticProbeGuard.isolated_identity("DegenerateAge-Test-x",true,"/tmp/DegenerateAge-Test-x"))
	assert(not DiagnosticProbeGuard.isolated_identity("DegenerateAge-Test-x",false,"/tmp/末法纪元"))
	assert(DiagnosticProbeGuard.isolated_identity("DegenerateAge-Test-x",false,"C:\\user\\DegenerateAge-Test-x"))
	print("[DiagnosticProbeGuardTest] 全部通过 ✅")
	get_tree().quit()
