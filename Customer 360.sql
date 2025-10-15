---================================================================================
---PREVIEW RAW DATA
---================================================================================
select top 100 * from customer_registered cr order by id;
select top 100 * from customer_transaction ct order by transaction_ID;

---================================================================================
---MAIN RFM PIPELINE
---================================================================================

declare @report_date as date = '2022-09-01';

with
-- ------------------------------------------------------------
-- Step 1: tính Recency / Frequency / Monetary (annualized)
-- ------------------------------------------------------------
rfm_base as (select ct.CustomerID,
                    cr.created_date,

                    -- Recency: số ngày kể từ lần mua gần nhất -> nhỏ = tốt
                    datediff(day, max(ct.Purchase_Date), @report_date) as [recency],

                    -- Frequency: số ngày mua riêng biệt / số ngày là KH x 365
                    -- annualized để công bằng giữa KH mới và cũ
                    round(1.0 * count(distinct ct.Purchase_Date) /
                          nullif(datediff(day, cr.created_date, @report_date), 0) * 365,
                          4)                                           as [frequency],

                    -- Monetary: tổng GMV / số ngày là KH x 365
                    round(1.0 * sum(ct.gmv) / nullif(datediff(day, cr.created_date, @report_date), 0) * 365,
                          4)                                           as [monetary]

             from Customer_Transaction ct
                      join
                  Customer_Registered cr
                  on
                      ct.CustomerID = cr.id
             where ct.CustomerID <> 0
             group by ct.CustomerID,
                      created_date
             ),
-- ------------------------------------------------------------
-- Step 2: xếp hạng từng metric bằng ROW_NUMBER
-- ------------------------------------------------------------
rfm_ranked as (select CustomerID,
                      recency,
                      frequency,
                      monetary,
                      -- xếp hạng tăng dần để lấy boundary
                      row_number() over (order by recency)   as rn_recency,
                      row_number() over (order by frequency) as rn_frequency,
                      row_number() over (order by monetary)  as rn_monetary,
                      count(*) over ()                       as total_customers
               from rfm_base
               ),
-- ------------------------------------------------------------
-- Step 3:  lấy giá trị boundary tại vị trí Q1 / Q2 / Q3
--          dùng MIN() bao ngoài để ép về 1 hàng (scalar)
--          vì ROW_NUMBER duy nhất -> MIN() = chính giá trị đ
--
--          Công thức vị trí quartile
--          Q1 = floor(N * 0.25)
--          Q2 = floor(N * 0.50)
--          Q3 = floor(N * 0.75)
-- ------------------------------------------------------------
rfm_quartiles as (select
                        -- Recency boundary
                        min(case when  rn_recency = floor(total_customers * 0.25) then recency end)      as r_q1,
                        min(case when  rn_recency = floor(total_customers * 0.50) then recency end)      as r_q2,
                        min(case when  rn_recency = floor(total_customers * 0.75) then recency end)      as r_q3,
                        -- Frequency boundary
                        min(case when rn_frequency = floor(total_customers * 0.25) then frequency end)   as f_q1,
                        min(case when rn_frequency = floor(total_customers * 0.50) then frequency end)   as f_q2,
                        min(case when rn_frequency = floor(total_customers * 0.75) then frequency end)   as f_q3,
                        -- Monetary boundary
                        min(case when rn_monetary = floor(total_customers * 0.25) then monetary end)     as m_q1,
                        min(case when rn_monetary = floor(total_customers * 0.50) then monetary end)     as m_q2,
                        min(case when rn_monetary = floor(total_customers * 0.75) then monetary end)     as m_q3
                 from rfm_ranked ),

-- ------------------------------------------------------------
-- Step 4: gán điểm 1-4 bằng cách so sánh với boundary
-- ------------------------------------------------------------

rfm_scores as (select r.CustomerID,
                      r.recency,
                      r.frequency,
                      r.monetary,

                      -- R Score: recency thấp = mua gần = điểm cao
                      case
                          when r.recency < q.r_q1 then 4
                          when r.recency < q.r_q2 then 3
                          when r.recency < q.r_q3 then 2
                          else 1
                          end as R,

                      -- F Score: frequency cao = mua nhiê = điểm cao
                      case
                          when r.frequency >= q.f_q3 then 4
                          when r.frequency >= q.f_q2 then 3
                          when r.frequency >= q.f_q1 then 2
                          else 1
                          end as F,


                      -- M Score: monetary cao = chi nhiều = điểm cao
                      case
                          when r.monetary >= q.m_q3 then 4
                          when r.monetary >= q.m_q2 then 3
                          when r.monetary >= q.m_q1 then 2
                          else 1
                          end as M
               from rfm_ranked r
                        cross join rfm_quartiles q),

-- ------------------------------------------------------------
-- Step 5: ghép điểm và phân nhóm
-- ------------------------------------------------------------
rfm_final as (select CustomerID,
                     recency,
                     frequency,
                     monetary,
                     R,
                     F,
                     M,
                     concat(R, F, M) as rfm_score,

                     case concat(R, F, M)
                         when '444' then 'VIP customers'
                         when '443' then 'VIP customers'
                         when '434' then 'VIP customers'
                         when '344' then 'VIP customers'
                         when '334' then 'VIP customers'

                         when '433' then 'Loyal customers'
                         when '424' then 'Loyal customers'
                         when '423' then 'Loyal customers'
                         when '414' then 'Loyal customers'
                         when '413' then 'Loyal customers'
                         when '343' then 'Loyal customers'
                         when '333' then 'Loyal customers'
                         when '324' then 'Loyal customers'
                         when '323' then 'Loyal customers'
                         when '314' then 'Loyal customers'
                         when '313' then 'Loyal customers'

                         when '442' then 'Potential customers'
                         when '432' then 'Potential customers'
                         when '422' then 'Potential customers'
                         when '412' then 'Potential customers'
                         when '342' then 'Potential customers'
                         when '332' then 'Potential customers'
                         when '322' then 'Potential customers'
                         when '312' then 'Potential customers'
                         when '242' then 'Potential customers'
                         when '233' then 'Potential customers'
                         when '244' then 'Potential customers'
                         when '243' then 'Potential customers'
                         when '234' then 'Potential customers'
                         when '224' then 'Potential customers'
                         when '223' then 'Potential customers'
                         when '214' then 'Potential customers'
                         when '213' then 'Potential customers'

                         else 'Visiting customers'
                         end         as customer_group

              from rfm_scores)

-- ------------------------------------------------------------
-- OUTPUT
-- ------------------------------------------------------------

select
    CustomerID,
    recency,
    frequency,
    monetary,
    R,
    F,
    M,
    rfm_score,
    customer_group
into project_customer_rfm_score
from
    rfm_final
/*
order by
    customer_group,
    rfm_score,
    CustomerID;

-- ------------------------------------------------------------
-- BONUS: validate kết quả
-- ------------------------------------------------------------

select
    customer_group,
    count(*)                                    as total_customer,
    cast(count(*) * 100.0
        / sum(count(*)) over() as decimal(5,2))  as pct_share,
    cast(avg(recency) as decimal(8,2))          as avg_recency,
    cast(avg(frequency) as decimal(8,2))        as avg_frequency,
    cast(avg(monetary) as decimal(8,2))         as avg_monetary
from
    rfm_final
group by
    customer_group
order by
    case customer_group
        when 'VIP customers'        then 1
        when 'Loyal customers'      then 2
        when 'Potential customers'  then 3
        when 'Visiting customers'   then 4
    end;


