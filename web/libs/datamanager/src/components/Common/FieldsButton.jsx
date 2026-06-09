import { Button, Checkbox, Dropdown } from "@humansignal/ui";
import { inject, observer } from "mobx-react";
import React from "react";
import { cn } from "../../utils/bem";
import { Menu } from "./Menu/Menu";

const injector = inject(({ store }) => {
  return {
    columns: Array.from(store.currentView?.targetColumns ?? []),
  };
});

const isEnterpriseColumn = (col) => col.enterprise_badge ?? col.original?.enterprise_badge;

const withoutEnterpriseColumns = (columns) =>
  columns
    .filter((col) => !isEnterpriseColumn(col))
    .map((col) => {
      if (!col.children) return col;

      return {
        ...col,
        children: col.children.filter((child) => !isEnterpriseColumn(child)),
      };
    })
    .filter((col) => !col.children || col.children.length > 0);

const FieldsMenu = observer(({ columns, WrapperComponent, onClick, onReset, selected, resetTitle }) => {
  const MenuItem = (col, onClick) => {
    const shouldDisable = col.disabled;

    const titleContent = <span>{col.title}</span>;

    return (
      <Menu.Item key={col.key} name={col.key} onClick={onClick} disabled={shouldDisable}>
        {WrapperComponent && col.wra !== false ? (
          <WrapperComponent column={col} disabled={shouldDisable}>
            {titleContent}
          </WrapperComponent>
        ) : (
          <span className="flex items-center justify-between w-full gap-base">{titleContent}</span>
        )}
      </Menu.Item>
    );
  };

  const visibleColumns = withoutEnterpriseColumns(columns);

  return (
    <Menu size="small" selectedKeys={selected ? [selected] : ["none"]} closeDropdownOnItemClick={false}>
      {onReset &&
        MenuItem(
          {
            key: "none",
            title: resetTitle ?? "Default",
            wrap: false,
          },
          onReset,
        )}

      {visibleColumns.map((col) => {
        if (col.children) {
          return (
            <Menu.Group key={col.key} title={col.title}>
              {col.children.map((col) => MenuItem(col, () => onClick?.(col)))}
            </Menu.Group>
          );
        }
        if (!col.parent) {
          return MenuItem(col, () => onClick?.(col));
        }

        return null;
      })}
    </Menu>
  );
});

export const FieldsButton = injector(
  ({
    columns,
    size,
    style,
    wrapper,
    title,
    icon,
    className,
    trailingIcon,
    onClick,
    onReset,
    resetTitle,
    filter,
    selected,
    tooltip,
    tooltipTheme = "dark",
    openUpwardForShortViewport = true,
    "data-testid": dataTestId,
  }) => {
    const content = [];

    if (title) content.push(<React.Fragment key="f-button-title">{title}</React.Fragment>);

    const renderButton = () => {
      return (
        <Button
          variant="neutral"
          size="small"
          look="outlined"
          leading={icon}
          trailing={trailingIcon}
          data-testid={dataTestId}
        >
          {content.length ? content : null}
        </Button>
      );
    };

    return (
      <Dropdown.Trigger
        content={
          <FieldsMenu
            columns={filter ? columns.filter(filter) : columns}
            WrapperComponent={wrapper}
            onClick={onClick}
            size={size}
            onReset={onReset}
            selected={selected}
            resetTitle={resetTitle}
          />
        }
        style={{ maxHeight: 280, overflow: "auto" }}
        openUpwardForShortViewport={openUpwardForShortViewport}
      >
        {tooltip ? (
          <div className={`${cn("field-button").toClassName()} h-[40px] flex items-center`} style={{ zIndex: 1000 }}>
            <Button
              tooltip={tooltip}
              variant="neutral"
              size={size}
              look="outlined"
              leading={icon}
              trailing={trailingIcon}
              data-testid={dataTestId}
            >
              {content.length ? content : null}
            </Button>
          </div>
        ) : (
          renderButton()
        )}
      </Dropdown.Trigger>
    );
  },
);

FieldsButton.Checkbox = observer(({ column, children, disabled }) => {
  const shouldDisable = disabled;

  return (
    <div className="w-full flex items-center justify-between gap-tight">
      <div className="flex-1 flex items-center min-w-0 overflow-hidden">
        <Checkbox
          size="small"
          checked={!column.is_hidden}
          onChange={column.toggleVisibility}
          disabled={shouldDisable}
          className="w-full"
        >
          {children}
        </Checkbox>
      </div>
    </div>
  );
});
