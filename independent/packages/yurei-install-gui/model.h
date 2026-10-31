#pragma once
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>
#include <QVector>

struct Disk {
    QString path, model, majorMinor;
    quint64 bytes = 0;
};

inline bool hasMountsOrUnknown(const QJsonObject &node) {
    if (!node.contains("mountpoints") || !node.value("mountpoints").isArray()) return true;
    for (const auto &point : node.value("mountpoints").toArray())
        if (!point.isNull() && (!point.isString() || !point.toString().isEmpty())) return true;
    for (const auto &child : node.value("children").toArray())
        if (hasMountsOrUnknown(child.toObject())) return true;
    return false;
}

inline QVector<Disk> eligibleDisks(const QByteArray &json, quint64 minimum, QString *error = nullptr) {
    QJsonParseError parse;
    const auto document = QJsonDocument::fromJson(json, &parse);
    if (parse.error != QJsonParseError::NoError || !document.object().value("blockdevices").isArray()) {
        if (error) *error = "Could not read the disk inventory.";
        return {};
    }
    QVector<Disk> disks;
    const QRegularExpression wholeDisk("^/dev/(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$");
    for (const auto &value : document.object().value("blockdevices").toArray()) {
        const auto node = value.toObject();
        const auto ro = node.value("ro");
        const bool writable = (ro.isBool() && !ro.toBool()) || (ro.isDouble() && ro.toInt() == 0);
        const auto size = node.value("size");
        const quint64 bytes = size.isString() ? size.toString().toULongLong() : quint64(qMax(0.0, size.toDouble()));
        const QString path = node.value("path").toString();
        if (node.value("type").toString() != "disk" || !writable || hasMountsOrUnknown(node)
            || bytes < minimum || !wholeDisk.match(path).hasMatch()) continue;
        const QString majorMinor = node.value("maj:min").toString();
        if (!QRegularExpression("^[0-9]+:[0-9]+$").match(majorMinor).hasMatch()) continue;
        disks.append({path, node.value("model").toString().trimmed(), majorMinor, bytes});
    }
    return disks;
}

struct InstallRequest {
    QString user, hostname, password, repeat, rootPassword, rootRepeat;
    QString validationError() const {
        if (!QRegularExpression("^[a-z_][a-z0-9_-]{0,31}$").match(user).hasMatch() || user == "root")
            return "Choose a lowercase user name other than root.";
        if (!QRegularExpression("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$").match(hostname).hasMatch())
            return "Use a computer name made of letters, digits and internal hyphens.";
        if (password.size() < 8 || password != repeat) return "Use matching passwords of at least eight characters.";
        if (rootPassword.size() < 8 || rootPassword != rootRepeat) return "The administrator passwords must match and contain at least eight characters.";
        for (const auto &secret : {password, rootPassword})
            if (secret.contains('\n') || secret.contains('\r') || secret.contains(QChar(0)))
                return "Passwords cannot contain line breaks or null characters.";
        return {};
    }
};

inline bool canInstall(const InstallRequest &request, const Disk &disk, bool live, bool preview,
                       bool acknowledged, const QString &confirmation) {
    return !preview && live && !disk.path.isEmpty() && request.validationError().isEmpty()
        && acknowledged && confirmation == "ERASE " + disk.path;
}

inline QStringList backendArguments(const InstallRequest &request, const Disk &disk) {
    return {"--disk", disk.path, "--hostname", request.hostname, "--user", request.user,
            "--expected-disk-bytes", QString::number(disk.bytes),
            "--expected-disk-device", disk.majorMinor, "--passwords-stdin", "--yes"};
}
