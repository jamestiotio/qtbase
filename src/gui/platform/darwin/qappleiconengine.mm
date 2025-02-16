// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#include "qappleiconengine_p.h"

#if defined(Q_OS_MACOS)
# include <AppKit/AppKit.h>
#elif defined (Q_OS_IOS)
# include <UIKit/UIKit.h>
#endif

#include <QtGui/qguiapplication.h>
#include <QtGui/qpainter.h>
#include <QtGui/qpalette.h>
#include <QtGui/qstylehints.h>

#include <QtGui/private/qcoregraphics_p.h>

QT_BEGIN_NAMESPACE

using namespace Qt::StringLiterals;

namespace {
auto *loadImage(const QString &iconName)
{
    static constexpr std::pair<QStringView, NSString *> iconMap[] = {
        {u"address-book-new", @"folder.circle"},
        {u"application-exit", @"xmark.circle"},
        {u"appointment-new", @"hourglass.badge.plus"},
        {u"call-start", @"phone.arrow.up.right"},
        {u"call-stop", @"phone.arrow.down.left"},
        {u"edit-clear", @"clear"},
        {u"edit-copy", @"doc.on.doc"},
        {u"edit-cut", @"scissors"},
        {u"edit-delete", @"delete.left"},
        {u"edit-find", @"magnifyingglass"},
        {u"edit-find-replace", @"arrow.up.left.and.down.right.magnifyingglass"},
        {u"edit-paste", @"clipboard"},
        {u"edit-redo", @"arrowshape.turn.up.right"},
        {u"edit-select-all", @""},
        {u"edit-undo", @"arrowshape.turn.up.left"},
    };
    const auto it = std::find_if(std::begin(iconMap), std::end(iconMap), [iconName](const auto &c){
        return c.first == iconName;
    });
    NSString *systemIconName = it != std::end(iconMap) ? it->second : iconName.toNSString();
#if defined(Q_OS_MACOS)
    return [NSImage imageWithSystemSymbolName:systemIconName accessibilityDescription:nil];
#elif defined(Q_OS_IOS)
    return [UIImage systemImageNamed:systemIconName];
#endif
}
}

QAppleIconEngine::QAppleIconEngine(const QString &iconName)
    : m_iconName(iconName), m_image(loadImage(iconName))
{
    if (m_image)
        [m_image retain];
}

QAppleIconEngine::~QAppleIconEngine()
{
    if (m_image)
        [m_image release];
}

QIconEngine *QAppleIconEngine::clone() const
{
    return new QAppleIconEngine(m_iconName);
}

QString QAppleIconEngine::key() const
{
    return u"QAppleIconEngine"_s;
}

QString QAppleIconEngine::iconName()
{
    return m_iconName;
}

bool QAppleIconEngine::isNull()
{
    return m_image == nullptr;
}

QList<QSize> QAppleIconEngine::availableIconSizes()
{
    const qreal devicePixelRatio = qGuiApp->devicePixelRatio();
    const QList<QSize> sizes = {
        {qRound(16 * devicePixelRatio), qRound(16 * devicePixelRatio)},
        {qRound(32 * devicePixelRatio), qRound(32 * devicePixelRatio)},
        {qRound(64 * devicePixelRatio), qRound(64 * devicePixelRatio)},
        {qRound(128 * devicePixelRatio), qRound(128 * devicePixelRatio)},
        {qRound(256 * devicePixelRatio), qRound(256 * devicePixelRatio)},
    };
    return sizes;
}

QList<QSize> QAppleIconEngine::availableSizes(QIcon::Mode, QIcon::State)
{
    return availableIconSizes();
}

QSize QAppleIconEngine::actualSize(const QSize &size, QIcon::Mode mode, QIcon::State state)
{
    return QIconEngine::actualSize(size, mode, state);
}

QPixmap QAppleIconEngine::pixmap(const QSize &size, QIcon::Mode mode, QIcon::State state)
{
    return scaledPixmap(size, mode, state, 1.0);
}

namespace {
#if defined(Q_OS_MACOS)
auto *configuredImage(const NSImage *image, const QColor &color)
{
    auto *config = [NSImageSymbolConfiguration configurationWithPointSize:48
                                               weight:NSFontWeightRegular
                                               scale:NSImageSymbolScaleLarge];
    if (@available(macOS 12, *)) {
        auto *primaryColor = [NSColor colorWithSRGBRed:color.redF()
                                                 green:color.greenF()
                                                  blue:color.blueF()
                                                 alpha:color.alphaF()];

        auto *colorConfig = [NSImageSymbolConfiguration configurationWithHierarchicalColor:primaryColor];
        config = [config configurationByApplyingConfiguration:colorConfig];
    }

    return [image imageWithSymbolConfiguration:config];
}
#elif defined(Q_OS_IOS)
auto *configuredImage(const UIImage *image, const QColor &color)
{
    auto *config = [UIImageSymbolConfiguration configurationWithPointSize:48
                                               weight:UIImageSymbolWeightRegular
                                               scale:UIImageSymbolScaleLarge];

    if (@available(iOS 15, *)) {
        auto *primaryColor = [UIColor colorWithRed:color.redF()
                                             green:color.greenF()
                                              blue:color.blueF()
                                             alpha:color.alphaF()];

        auto *colorConfig = [UIImageSymbolConfiguration configurationWithHierarchicalColor:primaryColor];
        config = [config configurationByApplyingConfiguration:colorConfig];
    }
    return [image imageByApplyingSymbolConfiguration:config];
}
#endif
}

namespace {
template <typename Image>
QPixmap imageToPixmap(const Image *image, QSizeF renderSize)
{
    if constexpr (std::is_same_v<Image, NSImage>)
        return qt_mac_toQPixmap(image, renderSize.toSize());
    else
        return QPixmap::fromImage(qt_mac_toQImage(image, renderSize.toSize()));
}
}

QPixmap QAppleIconEngine::scaledPixmap(const QSize &size, QIcon::Mode mode, QIcon::State state, qreal scale)
{
    const quint64 cacheKey = calculateCacheKey(mode, state);
    if (cacheKey != m_cacheKey || m_pixmap.size() != size || m_pixmap.devicePixelRatio() != scale) {
        QColor color;
        const QPalette palette;
        switch (mode) {
        case QIcon::Normal:
            color = palette.color(QPalette::Inactive, QPalette::Text);
            break;
        case QIcon::Disabled:
            color = palette.color(QPalette::Disabled, QPalette::Text);
            break;
        case QIcon::Active:
            color = palette.color(QPalette::Active, QPalette::Text);
            break;
        case QIcon::Selected:
            color = palette.color(QPalette::Active, QPalette::HighlightedText);
            break;
        }
        const auto *image = configuredImage(m_image, color);

        // the size we want is typically square, but the icon might not be. So
        // ask for a pixmap with the same aspect ratio as the icon, and then
        // center that within a pixmap of the requested size.
        QSizeF renderSize = size * scale;
        const bool aspectRatioAdjusted = image.size.width != image.size.height;
        if (aspectRatioAdjusted) {
            double aspectRatio = image.size.width / image.size.height;
            // don't grow
            if (aspectRatio < 1)
                renderSize.rwidth() = renderSize.height() * aspectRatio;
            else
                renderSize.rheight() = renderSize.width() / aspectRatio;
        }

        QPixmap iconPixmap = imageToPixmap(image, renderSize);
        iconPixmap.setDevicePixelRatio(scale);

        if (aspectRatioAdjusted) {
            m_pixmap = QPixmap(size * scale);
            m_pixmap.fill(Qt::transparent);
            m_pixmap.setDevicePixelRatio(scale);

            QPainter painter(&m_pixmap);
            const QSize offset = ((m_pixmap.deviceIndependentSize()
                                - iconPixmap.deviceIndependentSize()) / 2).toSize();
            painter.drawPixmap(offset.width(), offset.height(), iconPixmap);
        } else {
            m_pixmap = iconPixmap;
        }
        m_cacheKey = cacheKey;
    }
    return m_pixmap;
}

void QAppleIconEngine::paint(QPainter *painter, const QRect &rect, QIcon::Mode mode, QIcon::State state)
{
    const qreal scale = painter->device()->devicePixelRatio();
    // TODO: render the image directly if we don't have the pixmap yet and paint on an image
    painter->drawPixmap(rect, scaledPixmap(rect.size(), mode, state, scale));
}

QT_END_NAMESPACE
