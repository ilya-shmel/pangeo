function on_logline(logline)
	if contains({"curl", "wget", "lwp_download", "bash"}, logline:get("target.task.command", ""), "sub") and (logline:get("target.process.args", ""):search("^(?i)[a-zA-Z-]{0,10} [a-zA-Z0-9:.\/-]{11,100}\/[a-zA-Z0-9.-]{1,100}\.\bsh\b.*$") or logline:get("target.process.args") == nil) then
		grouper1:feed(logline)
	end
end
function on_grouped(grouped)
	local logline = grouped.aggregatedData.loglines[1]
	if grouped.aggregatedData.aggregated.total >= 1 then
		alert({template = [[Обнаружено получение содержимого файла формата sh из github и его исполнение посредством bash,
На хосте: "{{ .First.observer.host.ip }} - {{ .First.observer.host.hostname }}"
была выполнена команда: "{{ .First.target.task.command}} {{ .First.target.process.args}}".

Рекомендации по устранению инцидента:

Локализация инцидента:
Определить, на каких системах были получены и исполнены скрипты .sh из GitHub.
Просмотреть журналы доступа к GitHub для идентификации учетных записей, которые использовались для доступа к репозиториям.

Изолирование затронутых систем:
Немедленно изолировать системы, на которых были выполнены скрипты, чтобы предотвратить дальнейшее распространение возможного вредоносного ПО.

Анализ и аудит журналов безопасности:
Проверить журналы системы и Bash на предмет записей о выполнении скриптов и связанных событий.
Использовать инструменты анализа кода для оценки содержимого скриптов на предмет вредоносных действий.

Откат системных изменений:
Восстановить системы до последнего известного безопасного состояния.
Сменить пароли и ключи безопасности для всех учетных записей и систем, которые могли быть затронуты.

Обновление защитных мер:
Усилить политики безопасности и контроль за исполнением скриптов на рабочих станциях и серверах.
Реализовать строгий контроль доступа и аутентификацию для операций с внешними источниками кода, такими как GitHub, GitLab, BitBucket.]], risk_level = 8.0, asset_ip = logline:get_asset_data("observer.host.ip"), asset_hostname = logline:get_asset_data("observer.host.hostname"), asset_fqdn = logline:get_asset_data("observer.host.fqdn"), asset_mac = logline:get_asset_data(""), create_incident = true, incident_group = "", assign_to_customer = false, incident_identifier = "", logs = grouped.aggregatedData.loglines, trim_logs = 1})
		grouper1:clear()
	end
end

pattern = {
    { field = "target.task.command", values = {"wget", "curl", "lwp-download"}, count = 1 },
    { field = "target.task.command", values = {"bash"}, count = 1 },
}

grouper1 = grouper.new_pattern_matcher(
    {"observer.host.ip"},
    {"observer.host.ip"},
    pattern,
    "@timestamp,RFC3339Nano",
    "1m",
    on_grouped
)