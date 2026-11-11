-- Agenda pública: até 3 visitas, completando com previsões da fila.
-- Uma pessoa por quarta-feira; agendamentos existentes ocupam sua data.
drop view if exists public.visitas_publicas;

create view public.visitas_publicas
with (security_barrier = true, security_invoker = false)
as
with
hoje as (
  select (now() at time zone 'America/Sao_Paulo')::date as dia
),
agendadas as (
  select
    v.data_visita::date as data_visita,
    v.horario::text as horario,
    e.nome::text as enfermo_nome,
    concat_ws(', ',
      nullif(trim(e.endereco), ''),
      nullif(trim(e.numero), ''),
      nullif(trim(e.bairro), ''),
      nullif(trim(e.cidade), '')
    ) as endereco_completo,
    'Agendada'::text as origem,
    v.enfermo_id
  from public.visitas v
  join public.enfermos e on e.id = v.enfermo_id
  cross join hoje h
  where v.status = 'agendada'
    and v.data_visita::date >= h.dia
    and e.ativo = true
),
contagem as (
  select count(*)::int as total from agendadas
),
fila_base as (
  select
    e.id,
    e.nome,
    e.endereco,
    e.numero,
    e.bairro,
    e.cidade,
    max(v.data_visita)::date as ultima_data
  from public.enfermos e
  left join public.visitas v
    on v.enfermo_id = e.id
   and v.status = 'realizada'
  where e.ativo = true
    and not exists (
      select 1 from agendadas a where a.enfermo_id = e.id
    )
  group by e.id, e.nome, e.endereco, e.numero, e.bairro, e.cidade
),
fila as (
  select
    f.*,
    row_number() over (
      order by f.ultima_data nulls first, f.nome
    ) as posicao
  from fila_base f
),
proxima_quarta as (
  select
    h.dia + ((3 - extract(dow from h.dia)::int + 7) % 7)
      + case when extract(dow from h.dia)::int = 3 then 7 else 0 end as dia
  from hoje h
),
quartas_candidatas as (
  select
    (p.dia + (g.n * 7))::date as dia
  from proxima_quarta p
  cross join generate_series(0, 40) as g(n)
),
quartas_livres as (
  select
    q.dia,
    row_number() over (order by q.dia) as posicao
  from quartas_candidatas q
  where not exists (
    select 1 from agendadas a where a.data_visita = q.dia
  )
),
previstas as (
  select
    q.dia as data_visita,
    null::text as horario,
    f.nome::text as enfermo_nome,
    concat_ws(', ',
      nullif(trim(f.endereco), ''),
      nullif(trim(f.numero), ''),
      nullif(trim(f.bairro), ''),
      nullif(trim(f.cidade), '')
    ) as endereco_completo,
    'Previsão da fila'::text as origem,
    f.id as enfermo_id
  from fila f
  join quartas_livres q on q.posicao = f.posicao
  cross join contagem c
  where f.posicao <= greatest(0, 3 - c.total)
),
agenda_final as (
  select data_visita, horario, enfermo_nome, endereco_completo, origem from agendadas
  union all
  select data_visita, horario, enfermo_nome, endereco_completo, origem from previstas
)
select data_visita, horario, enfermo_nome, endereco_completo, origem
from agenda_final
order by data_visita, horario nulls last
limit 3;

revoke all on table public.visitas_publicas from public;
grant usage on schema public to anon;
grant select on table public.visitas_publicas to anon;
revoke all on table public.enfermos from anon;
revoke all on table public.visitas from anon;
